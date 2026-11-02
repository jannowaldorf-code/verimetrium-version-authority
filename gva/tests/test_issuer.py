import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import issuer

BASE_EVENT={
 'action':'opened',
 'repository':{'full_name':issuer.AUTHORITY},
 'issue':{'title':issuer.ISSUE_TITLE,'user':{'login':issuer.OWNER},'number':15,
          'body':json.dumps({'expected_next':'V1005.00','system':'SYS','role':'AUD','work':'GVA-K05-NEGATIVE-TEST','source_set_sha256':'a'*64})}}

class GvaTests(unittest.TestCase):
 def setUp(self):
  self.registry=issuer.verify()
 def test_genesis_and_next(self):
  n=len(self.registry['releases'])
  self.assertGreaterEqual(n,5)
  self.assertEqual(self.registry['next'],f'V{1000+n}.00')
  self.assertEqual([r['version'] for r in self.registry['releases'][:5]],issuer.LEGACY_VERSIONS)
 def test_valid_request(self):
  request,num=issuer.parse_issue(BASE_EVENT)
  self.assertEqual(num,15)
  self.assertEqual(request['system'],'SYS')
 def test_append(self):
  data=copy.deepcopy(self.registry)
  request,num=issuer.parse_issue(BASE_EVENT)
  request['expected_next']=data['next']
  before=data['next']
  row=issuer.append_request(data,request,num)
  self.assertEqual(row['version'],before)
  self.assertEqual(data['next'],f'V{1000+len(data["releases"])}.00')
  with tempfile.TemporaryDirectory() as temp:
   f=Path(temp)/'registry.json';f.write_text(json.dumps(data))
   self.assertEqual(issuer.verify(f)['next'],data['next'])
 def test_mutation_fail(self):
  self.registry['releases'][2]['source_set_sha256']='b'*64
  with tempfile.TemporaryDirectory() as temp:
   f=Path(temp)/'ledger.json';f.write_text(json.dumps(self.registry))
   with self.assertRaises(ValueError):issuer.verify(f)
 def test_duplicate_blocked(self):
  req,num=issuer.parse_issue(BASE_EVENT)
  req['expected_next']=self.registry['next']
  req['source_set_sha256']=self.registry['releases'][0]['source_set_sha256']
  with self.assertRaisesRegex(ValueError,'SOURCE_ALREADY_ISSUED'):issuer.append_request(copy.deepcopy(self.registry),req,num)
 def test_stale_version(self):
  req,num=issuer.parse_issue(BASE_EVENT);req['expected_next']='V1004.00'
  with self.assertRaisesRegex(ValueError,'STALE_EXPECTED_NEXT'):issuer.append_request(copy.deepcopy(self.registry),req,num)
 def test_two_issues_same_id(self):
  req,num=issuer.parse_issue(BASE_EVENT);d=copy.deepcopy(self.registry)
  req['expected_next']=d['next']
  issuer.append_request(d,req,num)
  req['expected_next']=d['next'];req['source_set_sha256']='b'*64
  with self.assertRaisesRegex(ValueError,'ISSUE_ALREADY_USED'):issuer.append_request(d,req,num)
 def test_unauthorized_user(self):
  e=copy.deepcopy(BASE_EVENT);e['issue']['user']['login']='intruder'
  with self.assertRaises(ValueError):issuer.parse_issue(e)
 def test_other_repository(self):
  e=copy.deepcopy(BASE_EVENT);e['repository']['full_name']='other/repo'
  with self.assertRaises(ValueError):issuer.parse_issue(e)
 def test_shell_injection(self):
  e=copy.deepcopy(BASE_EVENT);e['issue']['body']=e['issue']['body'].replace('GVA-K05-NEGATIVE-TEST','GVA-K05;$(rm -rf /)')
  with self.assertRaises(ValueError):issuer.parse_issue(e)
 def test_rel_fails(self):
  e=copy.deepcopy(BASE_EVENT);request=json.loads(e['issue']['body']);request['role']='REL';e['issue']['body']=json.dumps(request)
  with self.assertRaises(ValueError):issuer.parse_issue(e)
 def test_leaky_fields_fail(self):
  e=copy.deepcopy(BASE_EVENT);request=json.loads(e['issue']['body']);request['source_path']='secret.mq5';e['issue']['body']=json.dumps(request)
  with self.assertRaises(ValueError):issuer.parse_issue(e)
 def test_wrong_hash(self):
  e=copy.deepcopy(BASE_EVENT);request=json.loads(e['issue']['body']);request['source_set_sha256']='0x00';e['issue']['body']=json.dumps(request)
  with self.assertRaises(ValueError):issuer.parse_issue(e)
 def test_offline_issue_fails(self):
  from unittest.mock import patch
  with patch.dict('os.environ',{'GITHUB_ACTIONS':'false'}):
   with self.assertRaisesRegex(ValueError,'NO_REMOTE_ISSUER_AUTHORITY'):issuer.issue('nonexistent.json')
 def test_no_duplicated_sequence(self):
  d=copy.deepcopy(self.registry);d['releases'][2]['version']='V1001.00'
  with tempfile.TemporaryDirectory() as temp:
   f=Path(temp)/'registry.json';f.write_text(json.dumps(d))
   with self.assertRaises(ValueError):issuer.verify(f)
 def test_new_entry_tamper(self):
  d=copy.deepcopy(self.registry);req,num=issuer.parse_issue(BASE_EVENT);req['expected_next']=d['next'];issuer.append_request(d,req,num)
  d['releases'][-1]['work']='TAMPERED'
  with tempfile.TemporaryDirectory() as temp:
   f=Path(temp)/'ledger.json';f.write_text(json.dumps(d))
   with self.assertRaises(ValueError):issuer.verify(f)

if __name__=='__main__':unittest.main()
