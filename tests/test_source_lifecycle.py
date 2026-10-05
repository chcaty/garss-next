import unittest
from datetime import datetime, timezone, timedelta
from garss.source_lifecycle import prepare, update, effective_config
from garss.models import FeedSource, FeedResult
from garss.discovery import discover, parse_opml

class LifecycleTests(unittest.TestCase):
    def setUp(self):
        self.now = datetime(2026, 10, 3, tzinfo=timezone.utc)
        self.config = {'sources':[{'id':'a','feed_url':'https://a.test/rss','enabled':True},{'id':'b','feed_url':'https://b.test/rss','enabled':True}]}
        self.bad = FeedResult(FeedSource('a','A','','https://a.test/rss'),error='HTTP 404')
        self.good = FeedResult(FeedSource('b','B','','https://b.test/rss'))
    def test_archive_threshold_retry_and_recovery(self):
        state, _ = prepare(self.config, {}, self.now)
        for hours in [0,6,25]: update(state,[self.bad,self.good],self.now + timedelta(hours=hours))
        self.assertEqual(state['a']['status'],'archived')
        self.assertFalse(effective_config(self.config,state)['sources'][0]['enabled'])
        self.assertEqual(effective_config(self.config,state)['sources'][0]['collection_status'], 'archived')
        _, due = prepare(self.config,state,self.now + timedelta(days=2))
        self.assertEqual([s['id'] for s in due],['b'])
        _, due = prepare(self.config,state,self.now + timedelta(days=9))
        self.assertEqual(len(due),2)
        update(state,[FeedResult(self.bad.source),self.good],self.now + timedelta(days=9))
        self.assertEqual(state['a']['status'],'active')
        self.assertNotIn('archived_at',state['a'])
    def test_manual_disable_is_distinct_from_archive_and_preserves_authored_config(self):
        state, _ = prepare(self.config, {}, self.now)
        state['a']['status'] = 'archived'
        self.config['sources'][0]['enabled'] = False
        effective = effective_config(self.config, state)
        self.assertEqual(effective['sources'][0]['collection_status'], 'disabled')
        self.assertNotIn('collection_status', self.config['sources'][0])

    def test_broad_outage_and_manual_retry(self):
        state,_ = prepare(self.config,{},self.now)
        update(state,[self.bad,FeedResult(self.good.source,error='timeout')],self.now)
        self.assertEqual(state['a']['failures'],0)
        state['a'].update(status='archived',last_checked_at=self.now.isoformat().replace('+00:00', 'Z'))
        self.config['sources'][0]['recheck_requested_at'] = self.now.isoformat()
        state,due = prepare(self.config,state,self.now)
        self.assertEqual(state['a']['status'],'pending')
        self.assertEqual(len(due),2)
    def test_discovery_dedup_validation_and_weekly_limit(self):
        directory={'url':'https://directory.test/opml','page':'https://directory.test','category':'测试'}
        payload=b'<opml><body><outline xmlUrl="https://a.test/rss"/><outline text="New" xmlUrl="https://new.test/rss"/><outline xmlUrl="https://new.test/rss#fragment"/><outline xmlUrl="javascript:no"/></body></opml>'
        checks=[]
        def check(item): checks.append(item); return None
        doc=discover(self.config,[directory],{},self.now,download=lambda _:payload,check=check)
        self.assertEqual(len(doc['candidates']),1)
        self.assertEqual(len(checks),1)
        self.assertEqual(doc['candidates'][0]['discovered_from'],directory['page'])
        self.assertEqual(doc['directories'][0]['status'], 'ok')
        self.assertEqual(doc['directories'][0]['feed_count'], 2)
        self.assertEqual(doc['directories'][0]['checked_at'], self.now.isoformat().replace('+00:00', 'Z'))
        discover(self.config,[directory],doc,self.now+timedelta(days=1),download=lambda _:self.fail('should not fetch'),check=check)
        with self.assertRaises(ValueError): parse_opml(b'<!DOCTYPE x><opml/>',directory)
        doc=discover(self.config,[directory],{},self.now,download=lambda _:payload,check=lambda _:'not RSS')
        self.assertEqual(doc['candidates'],[])
        self.assertEqual(len(doc['rejected']),1)

    def test_each_category_gets_a_slot_and_directory_changes_bypass_cooldown(self):
        directories=[{'url':'https://directory.test/'+name,'page':'https://directory.test','category':name} for name in ['many','few']]
        def download(url):
            name=url.rsplit('/',1)[1]
            count=30 if name=='many' else 1
            return ('<opml><body>'+''.join(f'<outline xmlUrl="https://{name}.test/{i}"/>' for i in range(count))+'</body></opml>').encode()
        checked=[]
        doc=discover(self.config,directories,{},self.now,download=download,check=lambda item:checked.append(item) or None)
        self.assertEqual(len(checked),20)
        self.assertIn('few',{item['category'] for item in checked})
        calls=[]
        discover(self.config,directories+[{'url':'https://directory.test/new','page':'https://directory.test','category':'new'}],doc,self.now+timedelta(hours=1),download=lambda url:calls.append(url) or download(url),check=lambda _:None)
        self.assertEqual(len(calls),3)

    def test_directory_failure_is_visible_and_keeps_previous_candidates(self):
        directory = {'url': 'https://directory.test/opml', 'page': 'https://directory.test', 'category': 'news', 'updated_at': '2026-09-01T00:00:00Z'}
        candidate = {'id': 'new', 'feed_url': 'https://new.test/rss', 'category': 'news'}
        def failed(_):
            raise ValueError('invalid XML')
        doc = discover(self.config, [directory], {'candidates': [candidate]}, self.now, download=failed, check=lambda _: None)
        self.assertEqual(doc['candidates'], [candidate])
        self.assertEqual(doc['directories'][0]['status'], 'error')
        self.assertEqual(doc['directories'][0]['updated_at'], directory['updated_at'])
        self.assertIn('invalid XML', doc['directories'][0]['error'])
