import type {Article, Source} from './catalog.ts';
import {ReadingLibrary, type SavedArticle} from './reading-state.ts';

export const LEGACY_READING_KEY = 'garss-reading';
export const READING_STORAGE_PREFIX = 'garss-reading-v3:';
const OP = `${READING_STORAGE_PREFIX}op:`;
const RECOVERY = `${READING_STORAGE_PREFIX}recovery:`;
const QUARANTINE = `${READING_STORAGE_PREFIX}quarantine:`;
export type ReadingStorageStatus = {kind: 'ready' | 'recovery' | 'unavailable'; message: string; issueCount: number};
export type StoragePort = Pick<Storage, 'getItem' | 'setItem' | 'key' | 'length'>;
type RawRecord = {key: string; raw: string | null};
type Issue = RawRecord & {reason: string};
type Change = {field: 'read' | 'saved'; id: string; value: boolean; bookmark?: SavedArticle; snapshotOnly?: boolean; requiresAny?: string[]; derived?: boolean};
type Operation = {version: 3; clock: number; id: string; changes: Change[]; base?: {legacy: string | null}};
type Snapshot = {library: ReadingLibrary; clock: number; seeded: boolean; legacy: string | null; issues: Issue[]; records: RawRecord[]};
const isObject = (value: unknown): value is Record<string, unknown> => !!value && typeof value === 'object' && !Array.isArray(value);
const sameRaw = (a: RawRecord, b: RawRecord) => a.key === b.key && a.raw === b.raw;
const copy = (library: ReadingLibrary) => new ReadingLibrary(library.toJSON());

function differences(before: ReadingLibrary, after: ReadingLibrary): Change[] {
  const changes: Change[] = [];
  for (const field of ['read', 'saved'] as const) for (const id of new Set([...before[field], ...after[field]])) {
    const value = after[field].has(id);
    if (value !== before[field].has(id) || field === 'saved' && value && JSON.stringify(before.bookmarks.get(id)) !== JSON.stringify(after.bookmarks.get(id))) {
      changes.push({field, id, value, ...(field === 'saved' && before.saved.has(id) && value ? {snapshotOnly: true} : {}), ...(field === 'saved' && value && after.bookmarks.has(id) ? {bookmark: after.bookmarks.get(id)!} : {})});
    }
  }
  return changes;
}

function parseChanges(value: unknown): {changes: Change[]; damaged: boolean} {
  if (!Array.isArray(value)) return {changes: [], damaged: true};
  const changes: Change[] = []; let damaged = false;
  for (const item of value) {
    if (!isObject(item) || !['read', 'saved'].includes(String(item.field)) || typeof item.id !== 'string' || !item.id || typeof item.value !== 'boolean') { damaged = true; continue; }
    const change: Change = {field: item.field as Change['field'], id: item.id, value: item.value};
    if (item.snapshotOnly !== undefined) {
      if (item.snapshotOnly !== true || change.field !== 'saved' || !change.value) { damaged = true; continue; }
      change.snapshotOnly = true;
    }
    if (item.derived !== undefined) {
      if (item.derived !== true) { damaged = true; continue; }
      change.derived = true;
    }
    if (item.requiresAny !== undefined) {
      if (!change.value || !Array.isArray(item.requiresAny) || !item.requiresAny.length || item.requiresAny.some(id => typeof id !== 'string' || !id)) { damaged = true; continue; }
      change.requiresAny = item.requiresAny;
    }
    if (item.bookmark !== undefined) {
      const parsed = new ReadingLibrary({bookmarks: [item.bookmark]});
      const article = parsed.bookmarks.get(item.id);
      if (change.field !== 'saved' || !change.value || !article || parsed.issues.length) { damaged = true; continue; }
      change.bookmark = article;
    }
    changes.push(change);
  }
  return {changes, damaged};
}

/**
 * An append-only operation journal, not a last-writer-wins whole-library blob.
 * Each atomic localStorage write has an independent cryptographic UUID key. Tabs
 * never overwrite one another's operations. A Lamport clock plus UUID tie-breaker
 * gives every tab the same result; explicit false values are durable tombstones.
 * A first operation carries its legacy seed in the SAME atomic write. The original
 * legacy blob is never replaced/deleted, including on migration or recovery.
 * We intentionally do not compact without a cross-tab transactional protocol.
 */
export class ReadingStorage {
  readonly library = new ReadingLibrary();
  status: ReadingStorageStatus = {kind: 'ready', message: '', issueCount: 0};
  revision = 0;
  private baseline = new ReadingLibrary();
  private lastSnapshot: Snapshot | undefined;
  private port: StoragePort | undefined;
  private storageProvider: StoragePort | (() => StoragePort);
  private readonly uuid: () => string;
  // Immutable entries are decoded once. Key enumeration still detects other tabs.
  private decoded = new Map<string, {raw: string; value: unknown}>();

  constructor(storage: StoragePort | (() => StoragePort), uuid = () => crypto.randomUUID()) {
    this.uuid = uuid; this.storageProvider = storage;
    try { this.port = typeof storage === 'function' ? storage() : storage; this.refresh(); }
    catch { this.unavailable(); }
  }

  private unavailable() {
    this.status = {kind: 'unavailable', message: '无法读取或保存本机阅读记录。已停止改动，请检查浏览器存储权限和剩余空间后重试。', issueCount: this.lastSnapshot?.issues.length ?? 0};
  }

  private readRecords(): RawRecord[] {
    if (!this.port) throw Error('Storage unavailable');
    // localStorage has no multi-key snapshot. Never accept an interrupted key scan.
    const keys = () => {
      const found: string[] = [];
      for (let i = 0; i < this.port!.length; i++) {
        const key = this.port!.key(i);
        if (key === null) throw Error('Storage changed during scan');
        if (key.startsWith(OP) || key.startsWith(RECOVERY)) found.push(key);
      }
      return found.sort();
    };
    for (let attempt = 0; attempt < 3; attempt++) {
      const before = keys();
      const records = [{key: LEGACY_READING_KEY, raw: this.port.getItem(LEGACY_READING_KEY)}, ...before.map(key => ({key, raw: this.port!.getItem(key)}))];
      if (records.slice(1).some(record => record.raw === null)) continue;
      if (JSON.stringify(before) === JSON.stringify(keys())) return records;
    }
    throw Error('Storage is changing; retry rather than overwrite');
  }

  private decode(record: RawRecord): unknown {
    if (record.raw === null) return undefined;
    const cached = this.decoded.get(record.key);
    if (cached?.raw === record.raw) return cached.value;
    let value: unknown; try { value = JSON.parse(record.raw); } catch { value = undefined; }
    this.decoded.set(record.key, {raw: record.raw, value});
    return value;
  }

  private inspect(): Snapshot {
    const records = this.readRecords(), acknowledgements: RawRecord[] = [], issues: Issue[] = [];
    const issue = (record: RawRecord, reason: string) => {
      if (!acknowledgements.some(item => sameRaw(item, record)) && !issues.some(item => sameRaw(item, record))) issues.push({...record, reason});
    };
    // Recovery receipts contain verified raw backups, and acknowledge only those
    // exact bytes. A later corruption or an older app's write blocks again.
    for (const record of records.filter(record => record.key.startsWith(RECOVERY))) {
      const data = this.decode(record);
      if (isObject(data) && data.version === 3 && Array.isArray(data.records) && data.records.every(item =>
        isObject(item) && typeof item.key === 'string' && (typeof item.raw === 'string' || item.raw === null))) {
        acknowledgements.push(...data.records as RawRecord[]);
      }
    }
    for (const record of records.filter(record => record.key.startsWith(RECOVERY))) {
      const data = this.decode(record);
      if (!isObject(data) || data.version !== 3 || !Array.isArray(data.records) || !data.records.every(item =>
        isObject(item) && typeof item.key === 'string' && (typeof item.raw === 'string' || item.raw === null))) issue(record, '恢复记录损坏或版本不受支持');
    }
    const operations: {record: RawRecord; operation: Operation}[] = [];
    for (const record of records.filter(record => record.key.startsWith(OP))) {
      const data = this.decode(record);
      if (!isObject(data) || data.version !== 3 || typeof data.id !== 'string' || `${OP}${data.id}` !== record.key ||
          !Number.isSafeInteger(data.clock) || (data.clock as number) < 1 ||
          data.base !== undefined && (!isObject(data.base) || (data.base.legacy !== null && typeof data.base.legacy !== 'string'))) {
        issue(record, '阅读操作损坏或版本不受支持'); continue;
      }
      const parsed = parseChanges(data.changes);
      if (parsed.damaged) issue(record, '阅读操作包含损坏的记录');
      operations.push({record, operation: {version: 3, clock: data.clock as number, id: data.id, changes: parsed.changes, ...(data.base === undefined ? {} : {base: data.base as Operation['base']})}});
    }
    operations.sort((a, b) => a.operation.clock - b.operation.clock || (a.operation.id < b.operation.id ? -1 : a.operation.id > b.operation.id ? 1 : 0));
    const seeds = operations.filter(item => item.operation.base !== undefined);
    const legacy = seeds.length ? seeds[0].operation.base!.legacy : records[0].raw;
    if (seeds.length && records[0].raw !== legacy) issue(records[0], '旧版本页面改写了迁移前的阅读记录');
    for (const seed of seeds) if (seed.operation.base!.legacy !== legacy) issue(seed.record, '不同标签页迁移时的原始记录不一致');
    if (operations.length && !seeds.length) issue(operations[0].record, '迁移基线缺失');
    let value: unknown = {};
    if (legacy !== null) { try { value = JSON.parse(legacy); } catch { value = undefined; } }
    const library = new ReadingLibrary(value === undefined ? null : value);
    if (library.issues.length) issue({key: LEGACY_READING_KEY, raw: legacy}, library.issues.join('；'));
    const winners = new Map<string, {clock: number; value: boolean}>();
    const aliasTargets = new Map<string, Set<string>>();
    for (const {operation} of operations) for (const change of operation.changes) for (const alias of change.requiresAny ?? []) {
      const key = JSON.stringify([change.field, alias]);
      if (!aliasTargets.has(key)) aliasTargets.set(key, new Set());
      aliasTargets.get(key)!.add(change.id);
    }
    const removalTargets = (change: Change): string[] => {
      const targets = new Set([change.id]), pending = [change.id];
      while (pending.length) for (const target of aliasTargets.get(JSON.stringify([change.field, pending.pop()!])) ?? []) {
        if (!targets.has(target)) { targets.add(target); pending.push(target); }
      }
      return [...targets];
    };
    for (const {operation} of operations) {
      const prerequisites = new Map(operation.changes.filter(change => change.requiresAny).map(change => [change, change.requiresAny!.some(id => library[change.field].has(id))]));
      for (const original of operation.changes) for (const id of !original.value && !original.derived ? removalTargets(original) : [original.id]) {
        const change = {...original, id};
        if (change.requiresAny && !prerequisites.get(original)) continue;
        const entity = JSON.stringify([change.field, change.id]), winner = winners.get(entity);
        // Concurrent intent at the same Lamport revision uses removal/unread wins.
        if (winner?.clock === operation.clock && !winner.value && change.value) continue;
        // Background snapshot enrichment cannot resurrect a concurrent removal or
        // replace content chosen by a newer explicit save.
        if (change.snapshotOnly && (!library.saved.has(change.id) || library.bookmarks.has(change.id))) continue;
        if (!change.snapshotOnly) winners.set(entity, {clock: operation.clock, value: change.value});
        if (change.value) library[change.field].add(change.id); else library[change.field].delete(change.id);
        if (change.field === 'saved') {
          if (!change.value) library.bookmarks.delete(change.id);
          // A stale save/undo must not replace content another tab has already saved.
          // Deliberate remove-then-save clears the snapshot before adding a new one.
          else if (change.bookmark && !library.bookmarks.has(change.id)) library.bookmarks.set(change.id, change.bookmark);
        }
      }
    }
    return {library, clock: operations.at(-1)?.operation.clock ?? 0, seeded: !!seeds.length, legacy, issues, records};
  }

  private accept(snapshot: Snapshot) {
    if (JSON.stringify(this.baseline) !== JSON.stringify(snapshot.library)) this.revision++;
    this.library.replace(snapshot.library); this.baseline = copy(snapshot.library); this.lastSnapshot = snapshot;
    this.status = snapshot.issues.length ? {kind: 'recovery', message: `发现 ${snapshot.issues.length} 处本机记录损坏或版本冲突。原始数据已保留，阅读记录改动已暂停。请先导出备份，再确认恢复可读取的记录。`, issueCount: snapshot.issues.length} : {kind: 'ready', message: '', issueCount: 0};
  }

  refresh(): boolean {
    try {
      if (!this.port) this.port = typeof this.storageProvider === 'function' ? this.storageProvider() : this.storageProvider;
      this.accept(this.inspect()); return this.status.kind === 'ready';
    }
    catch { this.library.replace(this.baseline); this.unavailable(); return false; }
  }

  /** Commit only local intent relative to the last displayed state, then merge. */
  persist(reconciliation?: Article[]): boolean {
    const changes = differences(this.baseline, this.library);
    if (reconciliation) {
      const aliases = new Map(reconciliation.map(article => [article.id, article.legacy_ids ?? []]));
      for (const change of changes) {
        change.derived = true;
        if (!change.value || change.snapshotOnly) continue;
        const required = (aliases.get(change.id) ?? []).filter(id => this.baseline[change.field].has(id));
        if (required.length) change.requiresAny = required;
      }
    }
    try {
      const snapshot = this.inspect();
      if (snapshot.issues.length) { this.accept(snapshot); return false; }
      if (!changes.length) { this.accept(snapshot); return true; }
      if (!Number.isSafeInteger(snapshot.clock + 1)) throw Error('Revision overflow');
      const id = this.uuid(), key = OP + id;
      if (!id || this.port!.getItem(key) !== null) throw Error('Operation identity collision');
      const operation: Operation = {version: 3, id, clock: snapshot.clock + 1, changes, ...(!snapshot.seeded ? {base: {legacy: snapshot.legacy}} : {})};
      const raw = JSON.stringify(operation);
      // A single atomic append contains both migration and the requested changes.
      this.port!.setItem(key, raw);
      if (this.port!.getItem(key) !== raw) throw Error('Write could not be verified');
      this.accept(this.inspect());
      return this.status.kind === 'ready';
    } catch { this.library.replace(this.baseline); this.unavailable(); return false; }
  }

  reconcile(articles: Article[], sources: Source[]): boolean {
    if (!this.refresh()) return false;
    this.library.reconcile(articles, sources);
    return this.persist(articles);
  }

  /** Readable export keeps exact original strings, even when JSON cannot parse. */
  exportRecovery(): string {
    const records = this.readRecords();
    return JSON.stringify({format: 'shiyue-reading-recovery', version: 1, exportedAt: new Date().toISOString(), records}, null, 2);
  }

  /** Must be called only after explicit user confirmation in the recovery UI. */
  recover(): boolean {
    try {
      const snapshot = this.inspect();
      if (!snapshot.issues.length) { this.accept(snapshot); return true; }
      const records = snapshot.issues.map(({key, raw}) => ({key, raw}));
      const raw = JSON.stringify({version: 3, records});
      const id = this.uuid(), quarantine = QUARANTINE + id, receipt = RECOVERY + id;
      if (!id || this.port!.getItem(quarantine) !== null || this.port!.getItem(receipt) !== null) throw Error('Recovery identity collision');
      // Verify the independent quarantine BEFORE allowing any recovery. A crash
      // between writes leaves the original blocked, with its backup intact.
      this.port!.setItem(quarantine, raw);
      if (this.port!.getItem(quarantine) !== raw) throw Error('Backup not verified');
      this.port!.setItem(receipt, raw);
      if (this.port!.getItem(receipt) !== raw) throw Error('Recovery not verified');
      this.accept(this.inspect());
      return this.status.kind === 'ready';
    } catch { this.library.replace(this.baseline); this.unavailable(); return false; }
  }
}
