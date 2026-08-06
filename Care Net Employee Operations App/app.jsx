function AppShell({toast,pulseVariant}){
  const [authed,setAuthed]=React.useState(false);
  const [welcomed,setWelcomed]=React.useState(false);
  const [dayStarted,setDayStarted]=React.useState(false);
  const [tab,setTab]=React.useState('home');
  const [view,setView]=React.useState(null); // overlay flows
  const [wallet,setWallet]=React.useState(window.CNC.wallet.balance);
  const [pushNote,setPushNote]=React.useState(false);
  React.useEffect(()=>{if(dayStarted){const t=setTimeout(()=>setPushNote(true),5000);return()=>clearTimeout(t);}},[dayStarted]);
  const [result,setResult]=React.useState(null); // {blocked}
  const go=v=>setView(v);
  React.useEffect(()=>{window.__omGo=go;return()=>{delete window.__omGo;};},[]);
  const nav=<BottomNav active={tab} onNav={k=>{setView(null);setTab(k);}}/>;
  const finish=(blocked,msg)=>{setView(null);toast(msg||(blocked?'Submitted. Device set to do not use, unit manager notified.':'Inspection submitted and locked. Thank you.'));};
  if(!authed) return <LoginScreen onLogin={()=>setAuthed(true)}/>;
  if(!welcomed) return <WelcomeSplash onDone={()=>setWelcomed(true)}/>;
  if(!dayStarted) return <DayStart onSkip={()=>setDayStarted(true)} onProfile={()=>{setDayStarted(true);setView('profile');}} onHR={()=>{setDayStarted(true);setView('hr');}} onStarted={()=>{setDayStarted(true);toast('Jobcard MS038605 started and written to Supabase with your geofence and verification.');}}/>;
  let content;
  if(view==='scan') content=<ScanScreen label="Scan the equipment barcode" onCancel={()=>setView(null)} onFound={()=>setView('equipment')}/>;
  else if(view==='scan-cal') content=<ScanScreen label="Scan the device barcode" onCancel={()=>setView(null)} onFound={()=>setView('calibration')}/>;
  else if(view==='equipment') content=<ChecklistFlow title="Equipment inspection" checklist={window.CNC.equipChecklist} device={window.CNC.devices[0]} onBack={()=>setView(null)} onDone={b=>finish(b)}/>;
  else if(view==='facility') content=<FacilityScreen onBack={()=>setView(null)} onDone={b=>finish(b)}/>;
  else if(view==='vehicle') content=<VehicleScreen onBack={()=>setView(null)} onDone={b=>finish(b)}/>;
  else if(view==='calibration') content=<CalibrationScreen onBack={()=>setView(null)} onDone={b=>finish(b,b?'Out of tolerance. Device blocked, unit manager and hygiene lead notified.':'Calibration evidence submitted. In tolerance.')}/>;
  else if(view==='incident') content=<IncidentScreen onBack={()=>setView(null)} toast={toast}/>;
  else if(view==='clock') content=<ClockScreen nav={nav} toast={toast}/>;
  else if(view==='jobcard-history') content=<JobcardHistory onBack={()=>setView(null)} nav={nav}/>;
  else if(view==='survey') content=<SurveyScreen onBack={()=>setView(null)} nav={nav} toast={toast} wallet={wallet} addAmount={a=>setWallet(w=>w+a)}/>;
  else if(view==='wallet') content=<WalletScreen onBack={()=>setView(null)} nav={nav} wallet={wallet}/>;
  else if(view==='profile') content=<ProfileScreen onBack={()=>setView(null)} nav={nav} toast={toast} wallet={wallet} onWallet={()=>setView('wallet')}/>;
  else if(view==='hr') content=<HRScreen onBack={()=>setView(null)} nav={nav} toast={toast}/>;
  else if(view==='connect') content=<ConnectScreen onBack={()=>setView(null)} nav={nav} toast={toast}/>;
  else if(view==='speakout') content=<SpeakOutScreen onBack={()=>setView(null)}/>;
  else if(view==='news') content=<NewsScreen onBack={()=>setView(null)} nav={nav}/>;
  else if(tab==='home') content=<HomeScreen nav={nav} go={v=>{if(v==='inspect'){setTab('inspect');}else setView(v);}} pulseVariant={pulseVariant}/>;
  else if(tab==='jobcard') content=<JobcardScreen nav={nav} go={v=>{if(v==='inspect-tab'){setTab('inspect');}else setView(v);}}/>;
  else if(tab==='inspect') content=<InspectHub nav={nav} go={go}/>;
  else if(tab==='stock') content=<StockScreen nav={nav} toast={toast}/>;
  else content=<MoreScreen nav={nav} go={go} onLogout={()=>{setAuthed(false);setDayStarted(false);setTab('home');setView(null);}}/>;
  return <React.Fragment>
    {content}
    {pushNote&&<div onClick={()=>{setPushNote(false);setView(null);setTab('jobcard');}} style={{position:'absolute',top:10,left:10,right:10,zIndex:50,background:'#fff',borderRadius:'var(--radius-lg)',boxShadow:'var(--shadow-raised)',padding:'12px 14px',display:'flex',gap:12,alignItems:'flex-start',cursor:'pointer',animation:'cncdrop .25s var(--ease-standard)'}}>
      <img src="assets/logo-stacked.png" alt="" style={{width:34,borderRadius:8,border:'1px solid var(--border-subtle)',padding:2,flex:'none'}}/>
      <div style={{flex:1,minWidth:0}}>
        <div style={{display:'flex',gap:8,alignItems:'baseline'}}>
          <span style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:12.5}}>Care Net Operations</span>
          <span style={{fontSize:10.5,color:'var(--text-muted)',marginLeft:'auto'}}>now</span>
        </div>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,marginTop:2}}>Jobcard for tomorrow uploaded</div>
        <div style={{fontSize:12,color:'var(--text-muted)',marginTop:2,lineHeight:1.4}}>MS038609 · G4S Secure Solutions, Friday 7 August, with a note from the Operations Manager. Tap to view and start packing.</div>
      </div>
      <button onClick={e=>{e.stopPropagation();setPushNote(false);}} aria-label="Dismiss" style={{border:'none',background:'none',color:'var(--text-muted)',cursor:'pointer',padding:2,display:'flex'}}><I n="x" size={15}/></button>
    </div>}
  </React.Fragment>;
}

function Root(){
  const [surface,setSurface]=React.useState('app');
  const [scale,setScale]=React.useState(Math.min(1,(window.innerHeight-140)/892));
  React.useEffect(()=>{const f=()=>setScale(Math.min(1,(window.innerHeight-140)/892));window.addEventListener('resize',f);return()=>window.removeEventListener('resize',f);},[]);
  const [pulseVariant,setPulseVariant]=React.useState('heart');
  const [toasts,setToasts]=React.useState([]);
  const toast=msg=>{const id=Date.now();setToasts(t=>[...t,{id,msg}]);setTimeout(()=>setToasts(t=>t.filter(x=>x.id!==id)),4200);};
  return <div style={{height:'100vh',display:'flex',flexDirection:'column',background:'#E8E6E3'}}>
    <div style={{display:'flex',alignItems:'center',gap:14,padding:'10px 18px',background:'#fff',borderBottom:'1px solid var(--border-subtle)',flex:'none'}}>
      <img src="assets/logo-horizontal.png" alt="Care Net Consultants" style={{height:22}}/>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,color:'var(--text-muted)'}}>Employee Operations App · prototype</div>
      <div style={{marginLeft:'auto',display:'flex',gap:6,alignItems:'center'}}>
        <span style={{fontSize:11.5,color:'var(--text-muted)',fontFamily:'var(--font-heading)',fontWeight:600,marginRight:2}}>Pulse</span>
        {['standard','heart','protea'].map(v=><button key={v} onClick={()=>setPulseVariant(v)} style={{border:'1px solid '+(pulseVariant===v?'var(--cnc-red)':'var(--border-subtle)'),background:pulseVariant===v?'var(--red-tint)':'#fff',color:pulseVariant===v?'var(--cnc-red)':'var(--text-muted)',borderRadius:'var(--radius-pill)',padding:'4px 10px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11,cursor:'pointer',textTransform:'capitalize'}}>{v}</button>)}
        <span style={{width:1,height:20,background:'var(--border-subtle)',margin:'0 8px'}}></span>
        {[['app','Android app'],['backend','Web backend']].map(([k,l])=><button key={k} onClick={()=>setSurface(k)} style={{border:'none',background:surface===k?'var(--cnc-charcoal)':'transparent',color:surface===k?'#fff':'var(--text-muted)',borderRadius:'var(--radius-pill)',padding:'7px 16px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer'}}>{l}</button>)}
      </div>
    </div>
    <div style={{flex:1,minHeight:0,display:'flex',alignItems:'center',justifyContent:'center',overflow:'auto',padding:surface==='app'?'22px 0':'22px'}}>
      {surface==='app'?
        <div style={{transform:'scale('+scale+')',transformOrigin:'center center',height:892*scale,display:'flex',alignItems:'center'}}>
          <AndroidDevice width={400} height={860}>
            <div style={{height:'100%',position:'relative'}}><AppShell toast={toast} pulseVariant={pulseVariant}/></div>
          </AndroidDevice>
        </div>
        :
        <div style={{width:'100%',height:'100%',maxWidth:1280,background:'#fff',borderRadius:14,boxShadow:'var(--shadow-raised)',overflow:'hidden',display:'flex',flexDirection:'column'}}>
          <div style={{display:'flex',alignItems:'center',gap:8,padding:'9px 14px',background:'var(--surface-panel)',borderBottom:'1px solid var(--border-subtle)',flex:'none'}}>
            {['#FF5F57','#FEBC2E','#28C840'].map(c=><span key={c} style={{width:11,height:11,borderRadius:'50%',background:c}}></span>)}
            <span style={{margin:'0 auto',background:'#fff',borderRadius:'var(--radius-pill)',padding:'4px 22px',fontSize:11.5,color:'var(--text-muted)'}}>ops.carenetconsultants.co.za</span>
          </div>
          <div style={{flex:1,minHeight:0}}><Backend toast={toast}/></div>
        </div>}
    </div>
    <div style={{position:'fixed',bottom:'max(18px, calc(50vh - '+(892*scale/2+46)+'px))',left:'50%',transform:'translateX(-50%)',display:'flex',flexDirection:'column',gap:8,zIndex:200,alignItems:'center'}}>
      {toasts.map(t=><div key={t.id} style={{background:'var(--cnc-charcoal)',color:'#fff',borderRadius:'var(--radius-md)',padding:'11px 18px',fontSize:13,fontFamily:'var(--font-heading)',fontWeight:600,boxShadow:'var(--shadow-raised)',maxWidth:440,display:'flex',gap:10,alignItems:'center'}}><Pulse still white height={14} style={{alignSelf:'center'}}/>{t.msg}</div>)}
    </div>
  </div>;
}
ReactDOM.createRoot(document.getElementById('root')).render(<Root/>);
