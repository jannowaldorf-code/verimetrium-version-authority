#!/usr/bin/env python3
"""GitHub Free PUBLIC metadata ledger. No private sources, no trading certificates."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT/'gva'/'registry.json'
AUTHORITY = 'jannowaldorf-code/verimetrium-version-authority'
OWNER = 'jannowaldorf-code'
ISSUE_TITLE = 'GVA OFFICIAL VERSION REQUEST'
LEGACY_VERSIONS = ['V1000.00','V1001.00','V1002.00','V1003.00','V1004.00']
ROLES = {'BASE','DEV','AUD','REL'}
SYSTEMS = {'SYS','MT5','TV','SC','RESEARCH'}
HEX64 = re.compile(r'^[0-9a-f]{64}$')
VERS = re.compile(r'^V([0-9]+)\.00$')
WORK = re.compile(r'^[A-Z0-9][A-Z0-9_.-]{1,79}$')


def digest(obj):
    return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=False).encode('utf-8')).hexdigest()


def reject(code):
    raise ValueError('GVA_BLOCKED: '+code)


def entry_digest(entry):
    return digest({k:v for k,v in entry.items() if k!='entry_sha256'})


def verify(path=REGISTRY):
    data=json.loads(Path(path).read_text(encoding='utf-8'))
    if set(data)!={'schema','authority','visibility','legacy_anchor_sha256','next','releases'} or data['schema']!=5 or data['authority']!=AUTHORITY or data['visibility']!='PUBLIC_METADATA_ONLY':
        reject('SCHEMA_OR_AUTHORITY')
    rows=data['releases']
    if not isinstance(rows,list) or len(rows)<5:reject('MISSING_LEGACY_ANCHOR')
    if not isinstance(data['legacy_anchor_sha256'],str) or not HEX64.fullmatch(data['legacy_anchor_sha256']): reject('LEGACY_ANCHOR_INVALID')
    public_anchor=digest([{k:r.get(k) for k in ('version','source_set_sha256','legacy_seal')} for r in rows[:5]])
    # Immutable bootstrap anchor is pinned in code AND exported separately; after cutover all writes are ruleset-gated.
    if public_anchor!=PINNED_BOOTSTRAP_ANCHOR or data['legacy_anchor_sha256']!=PINNED_BOOTSTRAP_ANCHOR:reject('HISTORIC_ANCHOR_CHANGED')
    seen=set()
    for i,row in enumerate(rows):
        if not isinstance(row,dict) or row.get('version')!=f'V{1000+i}.00':reject('VERSION_SEQUENCE')
        if row.get('previous_entry_sha256')!=(rows[i-1]['entry_sha256'] if i else None):reject('BROKEN_CHAIN')
        if row.get('entry_sha256')!=entry_digest(row):reject('MUTATED_ENTRY')
        if row.get('role') not in ROLES or row.get('system') not in SYSTEMS:reject('INVALID_ROLE_SYSTEM')
        sha=row.get('source_set_sha256')
        if not isinstance(sha,str) or not HEX64.fullmatch(sha) or sha in seen:reject('DUPLICATE_OR_INVALID_SOURCE_HASH')
        seen.add(sha)
        if i<5 and (row.get('origin')!='LEGACY_IMPORT' or not HEX64.fullmatch(str(row.get('legacy_seal','')))):
            reject('LEGACY_RECORD_CHANGED')
        if i>=5:
            if set(row)!={'version','system','role','work','source_set_sha256','origin','issue_number','previous_entry_sha256','entry_sha256'}:reject('PUBLIC_METADATA_SCHEMA')
            if row['origin']!='PUBLIC_GITHUB_APP' or not isinstance(row['issue_number'],int) or row['issue_number']<=0 or not WORK.fullmatch(str(row['work'])):reject('BAD_PUBLIC_ENTRY')
            if row['role']=='REL':reject('REL_UNCERTIFIED')
    if data['next']!=f'V{1000+len(rows)}.00':reject('NEXT_COUNTER_DRIFT')
    return data


def parse_issue(event):
    issue=event.get('issue',{})
    if event.get('action')!='opened' or issue.get('title')!=ISSUE_TITLE:reject('WRONG_ISSUE_EVENT')
    if event.get('repository',{}).get('full_name')!=AUTHORITY or issue.get('user',{}).get('login')!=OWNER:reject('UNAUTHORIZED_ISSUER')
    if not isinstance(issue.get('number'),int) or issue['number']<1:reject('BAD_ISSUE_NUMBER')
    body=issue.get('body')
    if not isinstance(body,str) or len(body)>750:reject('REQUEST_INVALID')
    try:req=json.loads(body)
    except json.JSONDecodeError:reject('REQUEST_NOT_JSON')
    if not isinstance(req,dict) or set(req)!={'expected_next','system','role','work','source_set_sha256'}:reject('REQUEST_SCHEMA')
    if not isinstance(req['expected_next'],str) or not VERS.fullmatch(req['expected_next']):reject('EXPECTED_NEXT_INVALID')
    if req['system'] not in SYSTEMS or req['role'] not in ROLES or req['role']=='REL':reject('INVALID_OR_UNCERTIFIED_ROLE')
    if not isinstance(req['work'],str) or not WORK.fullmatch(req['work']):reject('UNSAFE_WORK_ID')
    if not isinstance(req['source_set_sha256'],str) or not HEX64.fullmatch(req['source_set_sha256']):reject('UNSAFE_SOURCE_HASH')
    return req,issue['number']


def append_request(data,req,issue_number):
    if req['expected_next']!=data['next']:reject('STALE_EXPECTED_NEXT')
    if any(r['source_set_sha256']==req['source_set_sha256'] for r in data['releases']):reject('SOURCE_ALREADY_ISSUED')
    if any(r.get('issue_number')==issue_number for r in data['releases']):reject('ISSUE_ALREADY_USED')
    row={'version':data['next'],'system':req['system'],'role':req['role'],'work':req['work'],
         'source_set_sha256':req['source_set_sha256'],'origin':'PUBLIC_GITHUB_APP',
         'issue_number':issue_number,'previous_entry_sha256':data['releases'][-1]['entry_sha256']}
    row['entry_sha256']=entry_digest(row)
    data['releases'].append(row)
    data['next']=f'V{1000+len(data["releases"])}.00'
    return row


def issue(event_file):
    if os.getenv('GITHUB_ACTIONS')!='true' or os.getenv('GITHUB_REPOSITORY')!=AUTHORITY or os.getenv('GITHUB_EVENT_NAME')!='issues':reject('NO_REMOTE_ISSUER_AUTHORITY')
    # Source tree must correspond to the remote main state before commit; compare expected SHA by git push fast-forward.
    if subprocess.check_output(['git','rev-parse','--abbrev-ref','HEAD'],cwd=ROOT,text=True).strip()!='main':reject('NOT_MAIN')
    data=verify()
    req,issue_id=parse_issue(json.loads(Path(event_file).read_text(encoding='utf-8')))
    row=append_request(data,req,issue_id)
    REGISTRY.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    verify()
    print('GVA_PUBLIC_ISSUED',row['version'],row['entry_sha256'])


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('command',choices=['verify','next','issue'])
    parser.add_argument('--event',default='')
    args=parser.parse_args()
    try:
        if args.command=='issue':issue(args.event)
        else:
            data=verify()
            print('PASS_PUBLIC_LEDGER_LOCAL_INTEGRITY' if args.command=='verify' else data['next'])
    except (ValueError, OSError, subprocess.CalledProcessError) as ex:
        print(ex,file=sys.stderr)
        sys.exit(1)

# Replaced by the audited genesis anchor at package build time.
PINNED_BOOTSTRAP_ANCHOR='f9c07c964b68459366b0fe31273681e665feb1c4a8208b85a561c07cfa5cc27f'
if __name__=='__main__':main()
