import unittest
from garss.source_request import apply_request, parse_request, source_hash, MARKER
import json


class SourceRequestTests(unittest.TestCase):
    def setUp(self):
        self.source = {'id': 'a', 'title': '中文来源', 'description': '原始摘要', 'category': '科技', 'feed_url': 'https://example.com/rss', 'enabled': True}
        self.config = {'schema_version': '1.0', 'repository': {'owner': 'chcaty', 'name': 'garss-next'}, 'sources': [self.source]}
        self.operation = {'id': 'a', 'before': source_hash(self.source), 'set': {'title': '新标题'}}
        self.request = {'version': 1, 'repository': 'chcaty/garss-next', 'operations': [self.operation]}
        self.event = {'repository': {'full_name': 'chcaty/garss-next', 'owner': {'login': 'chcaty'}}, 'sender': {'login': 'chcaty'}, 'issue': {'user': {'login': 'chcaty'}, 'body': MARKER+'\n```json\n'+json.dumps(self.request)+'\n```'}}

    def test_only_owner_requests_and_fixed_source_fields_are_accepted(self):
        self.assertEqual(parse_request(self.event), self.request)
        self.event['sender']['login'] = 'stranger'
        with self.assertRaises(ValueError):
            parse_request(self.event)
        self.operation['set'] = {'repository': {'owner': 'stranger'}}
        with self.assertRaises(ValueError):
            apply_request(self.config, self.request)

    def test_remote_additions_survive_and_repeated_requests_are_idempotent(self):
        self.config['sources'].append({**self.source, 'id': 'remote', 'feed_url': 'https://remote.test/rss'})
        updated = apply_request(self.config, self.request)
        self.assertEqual(updated['sources'][0]['title'], '新标题')
        self.assertEqual(updated['sources'][1], self.config['sources'][1])
        self.assertEqual(self.config['sources'][0]['title'], '中文来源')
        self.assertEqual(apply_request(updated, self.request), updated)

    def test_conflict_stops_the_entire_request_without_partial_updates(self):
        self.request['operations'].append({'id': 'new', 'before': None, 'set': {'title': 'Added'}})
        self.source['enabled'] = False
        with self.assertRaises(ValueError):
            apply_request(self.config, self.request)
        self.assertEqual(len(self.config['sources']), 1)
        self.assertEqual(self.source['title'], '中文来源')

    def test_deletion_requires_reviewed_version_and_does_not_remove_a_reused_id(self):
        self.operation.pop('set');self.operation['remove'] = True
        deleted = apply_request(self.config, self.request)
        self.assertEqual(deleted['sources'], [])
        self.assertEqual(apply_request(deleted, self.request), deleted)
        self.source['feed_url'] = 'https://new.test/rss'
        with self.assertRaises(ValueError):
            apply_request(self.config, self.request)
