// Modules 03–06: barcode scan, equipment, facility, vehicle, calibration
function ScanScreen({onFound,onCancel,label}){
  const [found,setFound]=React.useState(false);
  React.useEffect(()=>{const t=setTimeout(()=>setFound(true),1800);return()=>clearTimeout(t);},[]);
  React.useEffect(()=>{if(found){const t=setTimeout(onFound,900);return()=>clearTimeout(t);}},[found]);
  return <div style={{position:'absolute',inset:0,zIndex:5}}>
    <CamView scan frameLabel={label||'Scan the equipment barcode'} onCancel={onCancel} onCapture={()=>setFound(true)}>
      {found&&<div style={{position:'absolute',bottom:'14%',left:0,right:0,display:'flex',justifyContent:'center'}}>
        <div style={{background:'var(--cnc-green)',color:'#fff',borderRadius:'var(--radius-pill)',padding:'8px 18px',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,display:'flex',alignItems:'center',gap:8}}><I n="check" size={15}/>CNC-AUD-0031 · Audiometer</div>
      </div>}
    </CamView>
  </div>;
}

function DeviceHeader({device,blocked}){
  return <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',boxShadow:'var(--shadow-card)'}}>
    <div style={{display:'flex',alignItems:'center',gap:10}}>
      <div style={{flex:1}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:16}}>{device.device_type}</div>
        <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:2}}>{device.make} · {device.barcode} · SN {device.serial}</div>
      </div>
      {blocked?<Badge tone="red">Do not use</Badge>:<Badge tone="green">In service</Badge>}
    </div>
    <div style={{display:'flex',gap:16,marginTop:10,fontSize:12,color:'var(--text-muted)'}}>
      <span>Calibration valid to <strong style={{color:'var(--cnc-charcoal)'}}>{device.calibration_expiry}</strong></span>
      <span>{device.lifetime.toLocaleString('en-ZA')} lifetime tests</span>
    </div>
  </div>;
}

function ChecklistFlow({title,checklist,device,onDone,onBack,photoSlots}){
  const [res,setRes]=React.useState({});
  const [photos,setPhotos]=React.useState({});
  const [cam,setCam]=React.useState(null);
  const [confirm,setConfirm]=React.useState(false);
  const answered=checklist.every(c=>res[c.code]);
  const failedCrit=checklist.some(c=>c.critical&&res[c.code]==='fail');
  const fails=checklist.filter(c=>res[c.code]==='fail');
  const failPhotosOk=fails.every(f=>photos[f.code]);
  const overallOk=photos.__overall;
  const canSubmit=answered&&failPhotosOk&&overallOk;
  return <Screen pad bar={<AppBar onBack={onBack} title={title}/>}
    sticky={<StickyBar>
      <Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={!canSubmit} onClick={()=>setConfirm(true)}>Sign off and submit</Button>
    </StickyBar>}>
    {cam&&<CamView frameLabel={cam==='__overall'?'Overall condition photograph':'Evidence: '+checklist.find(c=>c.code===cam).label} onCancel={()=>setCam(null)} onCapture={()=>{setPhotos({...photos,[cam]:true});setCam(null);}}/>}
    {device&&<DeviceHeader device={device} blocked={failedCrit}/>}
    {failedCrit&&<Banner tone="red" title="Critical item failed">On submission this device is set to do not use and the unit manager is notified immediately. Only a super user can clear it.</Banner>}
    <SectionLabel>Checklist</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {checklist.map(c=><div key={c.code} style={{background:'#fff',border:res[c.code]==='fail'?'1.5px solid var(--cnc-red)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px'}}>
        <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:10}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5,flex:1}}>{c.label}</div>
          {c.critical&&<Tag>Critical</Tag>}
        </div>
        <SegPFN value={res[c.code]} onChange={v=>setRes({...res,[c.code]:v})}/>
        {res[c.code]==='fail'&&<div style={{marginTop:10,background:'var(--red-tint)',border:'1px solid rgba(237,27,36,.25)',borderRadius:'var(--radius-sm)',padding:10,display:'flex',flexDirection:'column',gap:8}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12,color:'var(--cnc-red)'}}>Photo evidence required for this failed item</div>
          <PhotoTile label={photos[c.code]?'Evidence captured':'Take evidence photograph'} taken={photos[c.code]} onTake={()=>setCam(c.code)}/>
        </div>}
      </div>)}
    </div>
    <SectionLabel>Overall condition</SectionLabel>
    <PhotoTile wide label={overallOk?'Overall photograph captured':'Take at least one overall condition photograph'} taken={overallOk} onTake={()=>setCam('__overall')}/>
    <Dialog open={confirm} title="Sign off this inspection?" onClose={()=>setConfirm(false)} footer={<React.Fragment><Button variant="secondary" size="sm" onClick={()=>setConfirm(false)}>Back</Button><Button size="sm" onClick={()=>onDone(failedCrit)}>Sign off</Button></React.Fragment>}>
      Your submission is locked once signed off. Corrections are new records that reference this one.
    </Dialog>
  </Screen>;
}
const {Tag} = window.CareNetConsultantsDesignSystem_7580a9;

function FacilityScreen({onDone,onBack}){
  const deps=window.CNC.departments;
  const [step,setStep]=React.useState(0);
  const [state,setState]=React.useState({});
  const [cam,setCam]=React.useState(false);
  const d=deps[step];
  const s=state[d]||{};
  const set=(k,v)=>setState({...state,[d]:{...s,[k]:v}});
  const done=deps.every(x=>state[x]&&state[x].photo&&state[x].clean&&state[x].waste);
  return <Screen pad bar={<AppBar onBack={onBack} title="Facility inspection · Trailer 1"/>}
    sticky={<StickyBar>
      {step>0&&<Button variant="secondary" onClick={()=>setStep(step-1)}>Previous</Button>}
      {step<deps.length-1?<Button style={{flex:1,justifyContent:'center'}} onClick={()=>setStep(step+1)}>Next station</Button>
      :<Button style={{flex:1,justifyContent:'center'}} disabled={!done} onClick={()=>onDone(false)}>Sign off and submit</Button>}
    </StickyBar>}>
    {cam&&<CamView frameLabel={d+' station'} onCancel={()=>setCam(false)} onCapture={()=>{set('photo',true);setCam(false);}}/>}
    <div style={{display:'flex',gap:5,overflow:'auto',paddingBottom:2,margin:'0 -2px',flex:'none'}}>
      {deps.map((x,i)=><button key={x} onClick={()=>setStep(i)} style={{flex:'none',border:'none',borderRadius:'var(--radius-pill)',padding:'7px 13px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12,cursor:'pointer',background:i===step?'var(--cnc-charcoal)':(state[x]&&state[x].photo?'var(--green-tint)':'#fff'),color:i===step?'#fff':(state[x]&&state[x].photo?'var(--cnc-green)':'var(--text-muted)'),border:i===step?'1px solid var(--cnc-charcoal)':'1px solid var(--border-subtle)'}}>{x}</button>)}
    </div>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:19}}>{d}</div>
    <PhotoTile wide label={s.photo?'Station photograph captured':'Photograph this station'} taken={s.photo} onTake={()=>setCam(true)}/>
    <SectionLabel>Checks</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {[['clean','Floors and surfaces clean'],['sign','Required signage displayed'],['cons','Consumables stocked'],['waste','Waste segregated correctly'],['safe','Fire extinguisher and first aid accessible']].map(([k,l])=>
        <div key={k} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'11px 14px'}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5,marginBottom:8}}>{l}</div>
          <SegPFN value={s[k]} onChange={v=>set(k,v)}/>
        </div>)}
    </div>
    <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center'}}>Station {step+1} of {deps.length}</div>
  </Screen>;
}

function VehicleScreen({onDone,onBack}){
  const shots=window.CNC.vehicleShots;
  const v=window.CNC.vehicles[0];
  const [taken,setTaken]=React.useState({});
  const [cam,setCam]=React.useState(null);
  const [odo,setOdo]=React.useState('');
  const [res,setRes]=React.useState({});
  const allShots=shots.every(s=>taken[s]);
  const allChecks=window.CNC.vehicleChecklist.every(c=>res[c.code]);
  return <Screen pad bar={<AppBar onBack={onBack} title="Vehicle pre trip"/>}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={!(allShots&&allChecks&&odo)} onClick={()=>onDone(false)}>Sign off and submit</Button></StickyBar>}>
    {cam&&<CamView frameLabel={cam+' photograph'} onCancel={()=>setCam(null)} onCapture={()=>{setTaken({...taken,[cam]:true});setCam(null);}}/>}
    <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',boxShadow:'var(--shadow-card)'}}>
      <div style={{display:'flex',alignItems:'center'}}>
        <div style={{flex:1}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:16}}>{v.registration}</div>
          <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:2}}>{v.make_model}</div>
        </div>
        <Badge tone="yellow">Disc expires in {v.disc_days} days</Badge>
      </div>
    </div>
    <SectionLabel>Required photographs · {Object.keys(taken).length} of 8</SectionLabel>
    <div style={{display:'grid',gridTemplateColumns:'repeat(4,1fr)',gap:8}}>
      {shots.map(s=><PhotoTile key={s} label={s} taken={taken[s]} onTake={()=>setCam(s)}/>)}
    </div>
    <Input label="Odometer reading (km)" placeholder="184 220" value={odo} onChange={e=>setOdo(e.target.value)}/>
    <div style={{fontSize:12,color:'var(--text-muted)',marginTop:-6}}>Typed as a number so service intervals can be projected from real distance.</div>
    <SectionLabel>Checklist</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {window.CNC.vehicleChecklist.map(c=><div key={c.code} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'11px 14px'}}>
        <div style={{display:'flex',alignItems:'center',gap:8,marginBottom:8}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5,flex:1}}>{c.label}</div>
          {c.critical&&<Tag>Critical</Tag>}
        </div>
        <SegPFN value={res[c.code]} onChange={x=>setRes({...res,[c.code]:x})}/>
      </div>)}
    </div>
  </Screen>;
}

function CalibrationScreen({onDone,onBack}){
  const d=window.CNC.devices[2]; // vision screener, will go out of tolerance
  const check=window.CNC.calibChecks['Vision screener'];
  const [val,setVal]=React.useState('');
  const [photos,setPhotos]=React.useState({});
  const [cam,setCam]=React.useState(null);
  const n=parseFloat(val);
  const out=val!==''&&!isNaN(n)&&Math.abs(n-check.fields[0].nominal)>check.fields[0].tol;
  const inTol=val!==''&&!isNaN(n)&&!out;
  const canSubmit=val!==''&&photos.reading&&photos.cert;
  return <Screen pad bar={<AppBar onBack={onBack} title="Calibration evidence"/>}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center',background:out?'var(--cnc-red)':undefined}} disabled={!canSubmit} onClick={()=>onDone(out)}>{out?'Submit and block device':'Submit calibration evidence'}</Button></StickyBar>}>
    {cam&&<CamView frameLabel={cam==='reading'?'Verification reading':'Calibration certificate in situ'} onCancel={()=>setCam(null)} onCapture={()=>{setPhotos({...photos,[cam]:true});setCam(null);}}/>}
    <DeviceHeader device={d} blocked={out}/>
    {out&&<div style={{background:'var(--cnc-red)',color:'#fff',borderRadius:'var(--radius-md)',padding:'16px 18px',display:'flex',alignItems:'center',gap:14}}>
      <I n="alert" size={26}/>
      <div>
        <div style={{fontFamily:'var(--font-display)',fontSize:24,letterSpacing:'.03em',lineHeight:1}}>DO NOT USE</div>
        <div style={{fontSize:12.5,opacity:.94,marginTop:4}}>Out of tolerance. The unit manager and occupational hygiene lead are notified on submission.</div>
      </div>
    </div>}
    <SectionLabel>{check.name}</SectionLabel>
    <div style={{background:'#fff',border:out?'1.5px solid var(--cnc-red)':inTol?'1.5px solid var(--cnc-green)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px'}}>
      <Input label={check.fields[0].k} placeholder={'Nominal '+check.fields[0].nominal+', tolerance ±'+check.fields[0].tol} value={val} onChange={e=>setVal(e.target.value)}/>
      {inTol&&<div style={{display:'flex',alignItems:'center',gap:6,color:'var(--cnc-green)',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12.5,marginTop:8}}><I n="check" size={15}/>In tolerance</div>}
      {out&&<div style={{display:'flex',alignItems:'center',gap:6,color:'var(--cnc-red)',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12.5,marginTop:8}}><I n="alert" size={15}/>Out of tolerance</div>}
    </div>
    <SectionLabel>Photographic proof</SectionLabel>
    <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:8}}>
      <PhotoTile label={photos.reading?'Reading captured':'Verification reading'} taken={photos.reading} onTake={()=>setCam('reading')}/>
      <PhotoTile label={photos.cert?'Certificate captured':'Certificate in situ'} taken={photos.cert} onTake={()=>setCam('cert')}/>
    </div>
    <div style={{fontSize:12,color:'var(--text-muted)',lineHeight:1.5}}>Tolerance bands are configured per device type by a super user. Certificate expiry warnings are raised at sixty and thirty days.</div>
  </Screen>;
}
Object.assign(window,{ScanScreen,ChecklistFlow,FacilityScreen,VehicleScreen,CalibrationScreen,DeviceHeader});
