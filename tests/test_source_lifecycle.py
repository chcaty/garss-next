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
        _, due = prepare(self.config,state,self.now + timedelta(days=2))
        self.assertEqual([s['id'] for s in due],['b'])
        _, due = prepare(self.config,state,self.now + timedelta(days=9))
        self.assertEqual(len(due),2)
        update(state,[FeedResult(self.bad.source),self.good],self.now + timedelta(days=9))
        self.assertEqual(state['a']['status'],'active')
        self.assertNotIn('archived_at',state['a'])
    def test_broad_outage_and_manual_retry(self):
        state,_ = prepare(self.config,{},self.now)
        update(state,[self.bad,FeedResult(self.good.source,error='timeout')],self.now)
        self.assertEqual(state['a']['failures'],0)
        state['a'].update(status='archived',last_checked_at=self.now.isoformat())
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
        discover(self.config,[directory],doc,self.now+timedelta(days=1),download=lambda _:self.fail('should not fetch'),check=check)
        with self.assertRaises(ValueError): parse_opml(b'<!DOCTYPE x><opml/>',directory)
        doc=discover(self.config,[directory],{},self.now,download=lambda _:payload,check=lambda _:'not RSS')
        self.assertEqual(doc['candidates'],[])
        self.assertEqual(len(doc['rejected']),1)
