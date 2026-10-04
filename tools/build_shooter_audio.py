#!/usr/bin/env python3
"""Deterministic variants from the licensed delivered sounds plus project-authored foley."""
import hashlib
import json
from pathlib import Path
import wave
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
RATE=22050

def read(name):
    with wave.open(str(ROOT/'assets/shooter/audio'/name),'rb') as pcm:
        data=np.frombuffer(pcm.readframes(pcm.getnframes()),dtype='<i2').astype(np.float64)/32768
        data=data.reshape(-1,pcm.getnchannels()).mean(axis=1)
        return np.interp(np.arange(round(len(data)*RATE/pcm.getframerate()))*pcm.getframerate()/RATE,np.arange(len(data)),data)

def build():
    output=ROOT/'assets/shooter/audio/banks';output.mkdir(exist_ok=True)
    banks={}
    def save(category,variant,signal):
        signal=np.asarray(signal,dtype=np.float64)
        signal*=0.70/max(np.max(np.abs(signal)),1e-9)
        signal[:min(32,len(signal))]*=np.linspace(0,1,min(32,len(signal)))
        signal[-min(256,len(signal)):]*=np.linspace(1,0,min(256,len(signal)))
        name=f'{category}-{variant}.wav'
        with wave.open(str(output/name),'wb') as pcm:
            pcm.setnchannels(1);pcm.setsampwidth(2);pcm.setframerate(RATE)
            pcm.writeframes((np.clip(signal,-1,1)*32767).astype('<i2').tobytes())
        banks.setdefault(category,[]).append(name)
    shot=read('shot.wav');reload=read('reload.wav');step=read('step.wav')
    for variant in range(3):
        pitched=np.interp(np.arange(len(shot))*(0.97+variant*0.03),np.arange(len(shot)),shot,right=0)
        save('shot_outdoor',variant,pitched)
        indoor=np.pad(pitched,(0,round(RATE*0.23)))
        for delay,gain in [(0.026,0.25),(0.053,0.18),(0.093,0.10),(0.16,0.055)]:
            offset=round(RATE*delay);indoor[offset:offset+len(pitched)]+=pitched*gain
        save('shot_indoor',variant,indoor)
    for surface in ['concrete','metal','ground']:
        for variant in range(4):
            rng=np.random.default_rng(407+variant+{'concrete':0,'metal':20,'ground':40}[surface]);length=round(RATE*0.16)
            t=np.arange(length)/RATE;noise=rng.uniform(-1,1,length);body=np.convolve(noise,np.ones(7)/7,mode='same')*np.exp(-t*48)
            base=np.pad(step,(0,max(0,length-len(step))))[:length]*0.7
            if surface=='metal':body+=np.sin(t*np.pi*2*(620+variant*37))*np.exp(-t*29)*0.12
            elif surface=='ground':body+=noise*np.exp(-t*20)*0.14
            else:body+=np.sin(t*np.pi*2*(100+variant*7))*np.exp(-t*40)*0.18
            save('step_'+surface,variant,base+body)
    for category,start,end in [('reload_out',0.0,0.25),('reload_in',0.45,0.78),('reload_charge',0.90,1.0)]:
        for variant in range(2):
            signal=reload[round(len(reload)*start):round(len(reload)*end)]
            signal=np.interp(np.arange(len(signal))*(0.98+variant*0.04),np.arange(len(signal)),signal,right=0)
            save(category,variant,signal)
    sources=['assets/shooter/audio/'+n for n in ['shot.wav','reload.wav','step.wav']]+['tools/build_shooter_audio.py']
    record={'version':1,'banks':banks,'source_hashes':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest()for n in sources},'output_hashes':{n:hashlib.sha256((output/n).read_bytes()).hexdigest()for names in banks.values()for n in names},'provenance':'Original licenses and attribution: assets/shooter/serious/manifest.json. Footstep additions and indoor tails are project-authored DSP, not field recordings.'}
    (output/'bank.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps({'ok':True,'banks':len(banks),'clips':len(record['output_hashes'])}))

if __name__=='__main__':build()
