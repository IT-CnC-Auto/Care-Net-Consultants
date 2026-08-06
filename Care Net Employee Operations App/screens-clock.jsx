// Module 02: Shared device multi user clocking with geofencing
function ClockScreen({nav,toast}){
  const teamNames=window.CNC.jobcards[0].team.map(t=>t.name);
  const [people,setPeople]=React.useState(window.CNC.roster.filter(p=>teamNames.includes(p.first+' '+p.last)));
  const [borrowed,setBorrowed]=React.useState(false);
  const [finger,setFinger]=React.useState(false);
  const [sel,setSel]=React.useState(null);        // person being verified
  const [phase,setPhase]=React.useState(null);    // cam | matching | result
  const [result,setResult]=React.useState(null);  // ok | flagged | offline
  const [offline,setOffline]=React.useState(false);
  const begin=p=>{setSel(p);setPhase('cam');};
  const capture=()=>{
    if(borrowed){setPhase('finger');return;}
    finish();
  };
  const finish=()=>{
    setPhase('matching');
    setTimeout(()=>{
      const r=offline?'offline':(sel.id==='p5'?'flagged':'ok');
      setResult(r);setPhase('result');
      setPeople(ps=>ps.map(x=>x.id===sel.id?{...x,status:x.status==='in'?'out':(r==='flagged'?'flagged':'in'),time:'07:0'+Math.floor(Math.random()*9)}:x));
    },1400);
  };
  const close=()=>{setSel(null);setPhase(null);setResult(null);};
  return <Screen pad bar={<AppBar title="Jobcard MS038605 team"/>} nav={nav}>
    <div style={{display:'flex',alignItems:'center',gap:8}}>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20,flex:1}}>Team clocking</div>
      <button onClick={()=>{setOffline(!offline);toast(offline?'Back online. 1 queued event synced.':'Offline mode. Events will queue on this device.');}} style={{display:'flex',alignItems:'center',gap:6,border:'1px solid var(--border-subtle)',background:offline?'var(--yellow-tint)':'#fff',color:offline?'#8a6100':'var(--text-muted)',borderRadius:'var(--radius-pill)',padding:'6px 12px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11.5,cursor:'pointer'}}><I n="offline" size={14}/>{offline?'Offline':'Online'}</button>
    </div>
    <div style={{display:'flex',alignItems:'center',gap:6,fontSize:12.5,color:'var(--text-muted)'}}>
      <I n="gps" size={14}/>Inside geofence: Murray & Dickson site, Modimolle · GPS locked
    </div>
    <Banner tone="blue" icon="user" title="Only your jobcard team clocks here">This roster shows the team allocated to jobcard MS038605 only. Everyone links through their own app to the operational dashboard.</Banner>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {people.map(p=>{
        const chip=p.status==='in'?<Badge tone="green">In since {p.time}</Badge>:p.status==='flagged'?<Badge tone="yellow">Flagged {p.time}</Badge>:<Badge>Not clocked in</Badge>;
        return <button key={p.id} onClick={()=>begin(p)} style={{display:'flex',alignItems:'center',gap:14,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',cursor:'pointer',textAlign:'left',minHeight:64,boxShadow:'var(--shadow-card)'}}>
          <Avatar name={p.first+' '+p.last} size={44}/>
          <span style={{flex:1,minWidth:0}}>
            <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:16}}>{p.first} {p.last}</span>
            <span style={{display:'block',fontSize:12.5,color:'var(--text-muted)',marginTop:2}}>{p.emp} · {p.role}</span>
          </span>
          {chip}
        </button>;})}
    </div>
    <label style={{display:'flex',gap:10,alignItems:'flex-start',background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px',cursor:'pointer',fontSize:12.5,lineHeight:1.5}}>
      <input type="checkbox" checked={borrowed} onChange={()=>setBorrowed(!borrowed)} style={{accentColor:'var(--cnc-red)',width:18,height:18,marginTop:1,flex:'none'}}/>
      <span><strong style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12.5}}>Team member without their phone?</strong><br/>They can clock in on this phone: tap their name, then verify with photo and fingerprint. Note: without their own phone, the survey wallet does not apply for the day.</span>
    </label>
    <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',padding:'4px 20px',lineHeight:1.5}}>Tap your name, then take a photograph to verify it is you. Clocking outside a geofence is allowed but reviewed.</div>
    {sel&&phase==='cam'&&<CamView frameLabel={'Verify '+sel.first+' '+sel.last} torchable={false} onCancel={close} onCapture={capture}/>}
    {sel&&phase==='finger'&&<div style={{position:'absolute',inset:0,background:'#101010',zIndex:6,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:18,color:'#fff',padding:28,textAlign:'center'}}>
      <div style={{width:96,height:120,border:'2.5px solid var(--cnc-red)',borderRadius:48,display:'flex',alignItems:'center',justifyContent:'center',position:'relative',overflow:'hidden'}}>
        <svg width="56" height="72" viewBox="0 0 56 72" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" opacity=".85"><path d="M28 12c-12 0-20 9-20 20v8"/><path d="M28 20c-8 0-13 6-13 12v12"/><path d="M28 28c-4 0-6 3-6 6v16"/><path d="M28 36v22"/><path d="M35 30c1 2 1 4 1 6v14"/><path d="M41 26c2 3 2 6 2 10v8"/></svg>
        <div className="cnc-scanline" style={{position:'absolute',left:6,right:6,height:2,background:'var(--cnc-red)'}}></div>
      </div>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:15}}>Photo matched. Now hold your finger on the scanner, {sel.first}…</div>
      <button onClick={()=>{finish();toast('Clocked on a teammate\u2019s phone: photo and fingerprint verified. Survey wallet not applicable for '+sel.first+' today.');}} style={{border:'1.5px solid #fff',background:'transparent',color:'#fff',borderRadius:'var(--radius-sm)',padding:'12px 26px',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,cursor:'pointer'}}>Prototype: finger scanned</button>
    </div>}
    {sel&&phase==='matching'&&<div style={{position:'absolute',inset:0,background:'#101010',zIndex:6,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:18,color:'#fff'}}>
      <div style={{width:64,height:64,borderRadius:'50%',border:'3px solid rgba(255,255,255,.2)',borderTopColor:'var(--cnc-red)',animation:'cncspin   .9s linear infinite'}}></div>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:15}}>Matching against your reference photograph…</div>
    </div>}
    {sel&&phase==='result'&&<ClockResult person={sel} result={result} onClose={close}/>}
  </Screen>;
}

function ClockResult({person,result,onClose}){
  const cfg={
    ok:{bg:'var(--cnc-green)',title:'Clocked in, '+person.first,body:'Photo verification passed with confidence 0.94. Your clock event has been written with GPS and geofence.',chip:null},
    flagged:{bg:'#B47B00',title:'Recorded, pending review',body:'The photo match returned confidence 0.58, below the threshold. Your event is saved and flagged for a super user to review. It is never discarded.',chip:'Flagged for review'},
    offline:{bg:'var(--cnc-charcoal)',title:'Queued on this device',body:'No connectivity. Your clock event is saved with the device time and GPS fix, and will sync automatically when the signal returns.',chip:'Offline captured'},
  }[result];
  return <div style={{position:'absolute',inset:0,background:cfg.bg,zIndex:6,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:16,color:'#fff',padding:28,textAlign:'center'}}>
    <div style={{width:72,height:72,borderRadius:'50%',background:'rgba(255,255,255,.16)',display:'flex',alignItems:'center',justifyContent:'center'}}>
      <I n={result==='ok'?'check':result==='flagged'?'alert':'offline'} size={34}/>
    </div>
    <div style={{fontFamily:'var(--font-display)',fontSize:34,letterSpacing:'.02em',lineHeight:1.05}}>{cfg.title}</div>
    {cfg.chip&&<span style={{background:'rgba(255,255,255,.18)',borderRadius:'var(--radius-pill)',padding:'5px 14px',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12,letterSpacing:'.06em',textTransform:'uppercase'}}>{cfg.chip}</span>}
    <div style={{fontSize:14,opacity:.92,maxWidth:290,lineHeight:1.55}}>{cfg.body}</div>
    <Pulse white height={36} style={{alignSelf:'center'}}/>
    <button onClick={onClose} style={{border:'1.5px solid #fff',background:'transparent',color:'#fff',borderRadius:'var(--radius-sm)',padding:'12px 30px',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14,cursor:'pointer',minHeight:48}}>Done</button>
  </div>;
}
Object.assign(window,{ClockScreen});
