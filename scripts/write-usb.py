#!/usr/bin/env python3
"""macOS: overwrite one identified external USB disk with an 8 GiB image, then read back and verify every byte."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import time

parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--image',type=Path,required=True)
parser.add_argument('--sha256',required=True)
parser.add_argument('--disk',required=True)
parser.add_argument('--status',type=Path,required=True)
parser.add_argument("--expect-size",type=int,required=True,help="exact TotalSize in bytes from diskutil info")
args=parser.parse_args()
if os.geteuid()!=0:
    raise SystemExit('Run with sudo from an authorized Mac terminal')
if not re.fullmatch(r'/dev/disk[0-9]+',args.disk):
    raise SystemExit('Expected whole-disk device identifier')
if not re.fullmatch(r'[0-9a-f]{64}',args.sha256):
    raise SystemExit('Expected exact SHA256')
size=8589934592
if args.image.stat().st_size!=size:
    raise SystemExit('Unexpected image size')
with args.image.open('rb') as source:
    if hashlib.file_digest(source,'sha256').hexdigest()!=args.sha256:
        raise SystemExit('Image hash mismatch; no device writes performed')
info=plistlib.loads(subprocess.check_output(['diskutil','info','-plist',args.disk]))
if not info.get('WholeDisk') or info.get('Internal') or info.get('BusProtocol')!='USB':
    raise SystemExit('Refusing non-whole/internal/non-USB device')
if info.get('TotalSize')!=args.expect_size:
    raise SystemExit('Refusing device with unexpected capacity')
raw=args.disk.replace('/dev/disk','/dev/rdisk',1)
def report(stage,done=0):
    record={'stage':stage,'bytes':done,'total':size,'disk':args.disk,'time':time.time()}
    args.status.write_text(json.dumps(record)+'\n')
    print(json.dumps(record),flush=True)
report('UNMOUNTING')
subprocess.run(['diskutil','unmountDisk',args.disk],check=True)
try:
    with args.image.open('rb') as source,open(raw,'r+b',buffering=0) as target:
        done=0
        for chunk in iter(lambda:source.read(4*1024*1024),b''):
            view=memoryview(chunk)
            while view:
                written=target.write(view)
                if not written: raise OSError('Short device write')
                view=view[written:]
            done+=len(chunk)
            if done%(256*1024*1024)==0: report('WRITING',done)
        if done!=size: raise RuntimeError('Image size changed')
    subprocess.run(['sync'],check=True)
    digest=hashlib.sha256()
    with open(raw,'rb',buffering=0) as target:
        done=0
        while done<size:
            chunk=target.read(min(4*1024*1024,size-done))
            if not chunk: raise OSError('Short device readback')
            digest.update(chunk); done+=len(chunk)
            if done%(256*1024*1024)==0: report('VERIFYING',done)
    if digest.hexdigest()!=args.sha256:
        raise RuntimeError('Full device readback hash mismatch')
    report('VERIFIED',size)
    subprocess.run(['diskutil','eject',args.disk],check=True)
    report('EJECTED',size)
    print('ASUS_USB_VERIFIED_AND_EJECTED SHA256='+args.sha256,flush=True)
except BaseException:
    report('FAILED')
    raise
