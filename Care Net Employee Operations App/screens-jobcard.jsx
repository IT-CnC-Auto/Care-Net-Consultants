// Daily jobcard, day start gate, client survey QR, digital wallet
function TomorrowCard({compact}){
  const t=window.CNC.tomorrowJobcard;
  const [open,setOpen]=React.useState(!compact);
  const [packed,setPacked]=React.useState({});
  return <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',boxShadow:'var(--shadow-card)',overflow:'hidden',flex:'none'}}>
    <button onClick={()=>setOpen(!open)} style={{display:'flex',alignItems:'center',gap:12,width:'100%',textAlign:'left',border:'none',background:'var(--blue-tint)',padding:'12px 14px',cursor:'pointer'}}>
      <span style={{width:34,height:34,borderRadius:'50%',background:'#fff',color:'var(--cnc-blue)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n="file" size={17}/></span>
      <span style={{flex:1,minWidth:0}}>
        <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:800,fontSize:13.5,color:'var(--cnc-blue)'}}>Tomorrow · {t.date}</span>
        <span style={{display:'block',fontSize:12,color:'var(--cnc-charcoal)',marginTop:2}}>{t.ref} · {t.client} · {t.booked} booked</span>
      </span>
      <span style={{color:'var(--cnc-blue)',display:'flex',transform:open?'rotate(90deg)':'none',transition:'transform var(--dur-fast)'}}><I n="chevR" size={18}/></span>
    </button>
    {open&&<div style={{padding:'12px 14px',display:'flex',flexDirection:'column',gap:12}}>
      <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:'10px 14px',fontSize:12.5}}>
        {[['Jobcard',t.ref],['Branch',t.branch],['Asset',t.asset],['Vehicle',t.vehicle],['Times',t.office_time+' · '+t.site_time],['Booked',t.booked+' medicals · '+t.medicals],['Address',t.address],['Travel',t.distance]].map(([k,v])=>
        <div key={k}><div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:10.5,letterSpacing:'.07em',textTransform:'uppercase',color:'var(--text-muted)'}}>{k}</div><div style={{marginTop:3,lineHeight:1.45}}>{v}</div></div>)}
      </div>
      <Banner tone="blue" icon="mail" title={'Note from the Operations Manager · '+t.uploaded}>{t.note}</Banner>
      <SectionLabel>Pack and prepare tonight</SectionLabel>
      <div style={{display:'flex',flexDirection:'column',gap:9}}>
        {t.packing.map((p,i)=><label key={i} style={{display:'flex',gap:10,alignItems:'flex-start',cursor:'pointer',fontSize:13,lineHeight:1.45,textDecoration:packed[i]?'line-through':'none',color:packed[i]?'var(--text-muted)':'var(--cnc-charcoal)'}}>
          <input type="checkbox" checked={!!packed[i]} onChange={()=>setPacked({...packed,[i]:!packed[i]})} style={{accentColor:'var(--cnc-red)',width:18,height:18,marginTop:1,flex:'none'}}/>{p}
        </label>)}
      </div>
      <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.5}}>Next day jobcards are always visible so the team can pack equipment, disposables and assets before the job starts. You receive a push notification whenever the Operations Manager uploads one or sends a note.</div>
    </div>}
  </div>;
}

function StarsStatic({value,size=14}){
  return <span style={{display:'inline-flex',gap:1,alignItems:'center'}}>
    {[1,2,3,4,5].map(n=><svg key={n} width={size} height={size} viewBox="0 0 24 24" fill={n<=Math.round(value)?'#FFB81C':'none'} stroke={n<=Math.round(value)?'#FFB81C':'#C9C9C9'} strokeWidth="1.8" strokeLinejoin="round"><path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.5L12 17.3l-5.9 3.2 1.3-6.5L2.5 9.4l6.6-.8L12 2.5z"/></svg>)}
    <span style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:size*.85,marginLeft:4,fontVariantNumeric:'tabular-nums'}}>{value.toFixed(1)}</span>
  </span>;
}

function WelcomeSplash({onDone}){
  const day=Math.floor(Date.now()/86400000);
  const qt=window.CNC.quotes[day%window.CNC.quotes.length];
  React.useEffect(()=>{const t=setTimeout(onDone,4200);return()=>clearTimeout(t);},[]);
  return <div onClick={onDone} style={{display:'flex',flexDirection:'column',height:'100%',background:'var(--cnc-red)',color:'#fff',alignItems:'center',justifyContent:'center',padding:32,textAlign:'center',gap:18,cursor:'pointer'}}>
    <FramedAvatar size={104} pulse/>
    <div style={{fontFamily:'var(--font-display)',fontSize:36,letterSpacing:'.02em',lineHeight:1.05,animation:'cncdrop .4s var(--ease-standard)'}}>Welcome back, Thandi</div>
    <Pulse white height={26} style={{maxWidth:220}}/>
    <div style={{animation:'cncdrop .5s var(--ease-standard) .15s backwards'}}>
      <div style={{fontSize:16.5,lineHeight:1.55,fontStyle:'italic',maxWidth:280}}>“{qt.q}”</div>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12.5,letterSpacing:'.06em',textTransform:'uppercase',opacity:.85,marginTop:10}}>{qt.a}</div>
    </div>
    <div style={{fontSize:11.5,opacity:.7,position:'absolute',bottom:26}}>A new thought every day · tap to continue</div>
  </div>;
}

function DayStart({onStarted,onSkip,onProfile,onHR}){
  const jc=window.CNC.jobcards[0];
  const [arrived,setArrived]=React.useState(false);
  const [cam,setCam]=React.useState(false);
  const [verifying,setVerifying]=React.useState(false);
  const verify=()=>{setCam(false);setVerifying(true);setTimeout(onStarted,1500);};
  return <div style={{display:'flex',flexDirection:'column',height:'100%',background:'var(--surface-panel)'}}>
    {cam&&<CamView frameLabel="Verify to start your jobcard" torchable={false} onCancel={()=>setCam(false)} onCapture={verify}/>}
    {verifying&&<div style={{position:'absolute',inset:0,background:'#101010',zIndex:6,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:18,color:'#fff'}}>
      <div style={{width:64,height:64,borderRadius:'50%',border:'3px solid rgba(255,255,255,.2)',borderTopColor:'var(--cnc-red)',animation:'cncspin .9s linear infinite'}}></div>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:15}}>Verifying and starting jobcard {jc.ref}…</div>
    </div>}
    <div style={{background:'var(--cnc-charcoal)',color:'#fff',padding:'26px 22px 18px',flex:'none'}}>
      <div style={{display:'flex',alignItems:'flex-start'}}>
        <img src="assets/logo-horizontal.png" alt="Care Net Consultants" style={{height:44,background:'#fff',borderRadius:8,padding:'8px 14px'}}/>
        <div style={{marginLeft:'auto'}}><AvatarMenu dark size={92} pulse onProfile={onProfile} onHR={onHR}/></div>
      </div>
      <div style={{fontFamily:'var(--font-display)',fontSize:28,letterSpacing:'.02em',lineHeight:1.05,marginTop:14}}>Your day, Thandi</div>
      <div style={{fontSize:13,opacity:.85,marginTop:4}}>{window.CNC.today}</div>
      <Pulse white height={26} style={{marginTop:10}}/>
    </div>
    <div className="cnc-scroll" style={{flex:1,overflow:'auto',overflowX:'hidden',padding:16,display:'flex',flexDirection:'column',gap:12}}>
      <SectionLabel>Allocated to you today</SectionLabel>
      <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',boxShadow:'var(--shadow-card)'}}>
        <div style={{display:'flex',alignItems:'center',gap:10}}>
          <div style={{flex:1}}>
            <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:16}}>{jc.ref} · {jc.client}</div>
            <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:2}}>{jc.branch} · {jc.asset} · {jc.booked} booked</div>
          </div>
          <Badge tone="blue">Travel job</Badge>
        </div>
        <div style={{display:'flex',flexDirection:'column',gap:6,marginTop:12,fontSize:12.5,color:'var(--cnc-charcoal)'}}>
          <div style={{display:'flex',gap:8,alignItems:'center'}}><I n="clock" size={14} style={{color:'var(--text-muted)'}}/>{jc.office_time} · {jc.site_time}</div>
          <div style={{display:'flex',gap:8,alignItems:'center'}}><I n="gps" size={14} style={{color:'var(--text-muted)'}}/>{jc.address} · {jc.distance}</div>
          <div style={{display:'flex',gap:8,alignItems:'center'}}><I n="truck" size={14} style={{color:'var(--text-muted)'}}/>{jc.vehicle}</div>
        </div>
      </div>
      <Banner tone={arrived?'green':'yellow'} icon={arrived?'check':'gps'} title={arrived?'Inside your job geofence':'You cannot start while travelling'}>
        {arrived?'Geofence confirmed: '+jc.geofence+'. You can start your jobcard.':'This is a travel job, so your geofence is the guesthouse address. Your jobcard opens at '+jc.start+' once you are inside the geofence: '+jc.geofence+'.'}
      </Banner>
      <TomorrowCard compact/>
      <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',overflow:'hidden',boxShadow:'var(--shadow-card)'}}>
        <div style={{position:'relative',height:110,background:'linear-gradient(160deg,#E8EFE6 0%,#DFE9E2 55%,#D8E4DC 100%)'}}>
          <svg style={{position:'absolute',inset:0,width:'100%',height:'100%'}} preserveAspectRatio="none" viewBox="0 0 340 110">
            <path d="M0 78 C60 70 90 84 150 76 S260 60 340 68" stroke="#fff" strokeWidth="7" fill="none"/>
            <path d="M60 0 C70 40 58 70 72 110" stroke="#fff" strokeWidth="4" fill="none"/>
            <path d="M210 0 C200 34 226 70 214 110" stroke="#fff" strokeWidth="4" fill="none"/>
            <circle cx="170" cy="56" r="34" fill="rgba(237,27,36,.12)" stroke="var(--cnc-red)" strokeWidth="1.5" strokeDasharray="5 4"/>
          </svg>
          <div style={{position:'absolute',left:'50%',top:'50%',transform:'translate(-50%,-90%)',color:'var(--cnc-red)'}}>
            <svg width="26" height="32" viewBox="0 0 24 30"><path d="M12 1C6.5 1 2 5.4 2 10.8 2 18 12 29 12 29s10-11 10-18.2C22 5.4 17.5 1 12 1Z" fill="var(--cnc-red)"/><circle cx="12" cy="10.5" r="4" fill="#fff"/></svg>
          </div>
          <span style={{position:'absolute',right:8,bottom:8,background:'rgba(255,255,255,.9)',borderRadius:'var(--radius-pill)',padding:'3px 10px',fontSize:10.5,fontFamily:'var(--font-heading)',fontWeight:600,color:'var(--text-muted)'}}>Geofence radius 200 m</span>
        </div>
        <div style={{padding:'11px 14px',display:'flex',alignItems:'center',gap:10}}>
          <div style={{flex:1,minWidth:0}}>
            <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12.5}}>{jc.geofence}</div>
            <div style={{fontSize:11.5,color:'var(--text-muted)',marginTop:2,fontVariantNumeric:'tabular-nums'}}>-24.7000939, 28.4058652</div>
          </div>
          <a href="https://www.google.com/maps?q=-24.7000939,28.4058652" target="_blank" style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12,color:'var(--cnc-red)',textDecoration:'none',border:'1px solid var(--cnc-red)',borderRadius:'var(--radius-sm)',padding:'7px 12px',flex:'none'}}>Open in Google Maps</a>
        </div>
      </div>
      <div style={{display:'flex',alignItems:'center',gap:10,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'10px 14px'}}>
        <span style={{color:'var(--cnc-green)',display:'flex',flex:'none'}}><I n="gps" size={17}/></span>
        <span style={{flex:1,fontSize:12,lineHeight:1.45,color:'var(--cnc-charcoal)'}}><strong style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12}}>Location services: on</strong><br/>On a company phone, location services stay on at all times. Clocking and jobcards cannot run without them.</span>
        <Badge tone="green">Always on</Badge>
      </div>
      <button onClick={()=>setArrived(!arrived)} style={{border:'1px dashed var(--border-subtle)',background:'#fff',color:'var(--text-muted)',borderRadius:'var(--radius-sm)',padding:'9px 14px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12,cursor:'pointer',alignSelf:'center'}}>Prototype: simulate {arrived?'leaving':'arriving at'} the geofence</button>
      <div style={{marginTop:'auto',display:'flex',flexDirection:'column',gap:8}}>
        <Button size="lg" style={{width:'100%',justifyContent:'center'}} disabled={!arrived} onClick={()=>setCam(true)} icon={<I n="camera" size={17}/>}>Verify me and start my jobcard</Button>
        <button onClick={onSkip} style={{border:'none',background:'none',color:'var(--cnc-red)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13,cursor:'pointer',padding:8}}>Browse the app without starting →</button>
        <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5}}>Facial verification against your reference photograph signs you on for the day and opens jobcard {jc.ref}.</div>
      </div>
    </div>
  </div>;
}

function JobcardScreen({nav,go}){
  const jc=window.CNC.jobcards[0];
  return <Screen pad bar={<AppBar title={'Jobcard '+jc.ref}/>} nav={nav}>
    <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'16px',boxShadow:'var(--shadow-card)'}}>
      <div style={{display:'flex',alignItems:'flex-start',gap:10}}>
        <div style={{flex:1}}>
          <div style={{fontFamily:'var(--font-display)',fontSize:24,letterSpacing:'.02em',lineHeight:1.05}}>{jc.client}</div>
          <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:4}}>{jc.ref} · {jc.branch}</div>
        </div>
        <Badge tone="green">Started 07:58</Badge>
      </div>
      <div style={{display:'flex',alignItems:'center',gap:8,marginTop:8}}>
        <StarsStatic value={4.8}/>
        <span style={{fontSize:11.5,color:'var(--text-muted)'}}>2 client reviews on this jobcard</span>
      </div>
      <Pulse height={20} style={{margin:'12px 0 2px'}}/>
      <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:'10px 14px',marginTop:10,fontSize:12.5}}>
        {[['Asset',jc.asset],['Vehicle',jc.vehicle],['Times',jc.office_time+' · '+jc.site_time],['Booked',jc.booked+' medicals · '+jc.medicals],['Quote / PO',jc.quote+' · '+jc.po],['Address',jc.address]].map(([k,v])=>
        <div key={k}><div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:10.5,letterSpacing:'.07em',textTransform:'uppercase',color:'var(--text-muted)'}}>{k}</div><div style={{marginTop:3,lineHeight:1.45}}>{v}</div></div>)}
      </div>
    </div>
    {jc.notes.length>0&&<Banner tone="yellow" title="Booking notes">{jc.notes.join(' ')}</Banner>}
    <SectionLabel>Tomorrow's jobcard · pack tonight</SectionLabel>
    <TomorrowCard compact/>
    <SectionLabel>Your team on this jobcard</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:8}}>
      {jc.team.map(t=><div key={t.name} style={{display:'flex',alignItems:'center',gap:12,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'11px 14px'}}>
        <Avatar name={t.name} size={36}/>
        <div style={{flex:1,minWidth:0}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5}}>{t.name}</div>
          <div style={{fontSize:12,color:'var(--text-muted)',marginTop:1}}>{t.duties}</div>
        </div>
      </div>)}
    </div>
    <SectionLabel>On this jobcard</SectionLabel>
    <ListRow icon="inspect" title="Inspect allocated assets" sub={jc.asset+' and vehicle only'} onClick={()=>go('inspect-tab')}/>
    <ListRow icon="speak" title="Quick approvals" sub="Ask your supervisor, sales or finance for an urgent decision" onClick={()=>go('connect')}/>
    <ListRow icon="camera" title="Client survey and review" sub="Star survey plus a ready written Google review" onClick={()=>go('survey')}/>
    <ListRow icon="file" title="My jobcard history" sub="Kept in your employee file for 12 months" onClick={()=>go('jobcard-history')}/>
    <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5,padding:'0 12px'}}>This jobcard was pushed to the app from the daily operations summary. You only see work and assets allocated to you.</div>
  </Screen>;
}

function JobcardHistory({onBack,nav}){
  return <Screen pad bar={<AppBar onBack={onBack} title="My jobcards"/>} nav={nav}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>Jobcard history</div>
    <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:-8}}>Retained in your employee file for 12 months</div>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {window.CNC.myJobcards.map(j=><div key={j.ref} style={{background:'#fff',border:j.flagged?'1.5px solid var(--cnc-red)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px'}}>
        <div style={{display:'flex',alignItems:'center',gap:12}}>
          <div style={{flex:1,minWidth:0}}>
            <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>{j.client}</div>
            <div style={{fontSize:12,color:'var(--text-muted)',marginTop:2}}>{j.ref} · {j.branch} · {j.date} · {j.hours}</div>
          </div>
          <Badge tone="green">{j.status}</Badge>
        </div>
        <div style={{display:'flex',alignItems:'center',gap:8,marginTop:8}}>
          <StarsStatic value={j.rating}/>
          <span style={{fontSize:11.5,color:'var(--text-muted)'}}>{j.reviews} review{j.reviews>1?'s':''}</span>
          {j.flagged&&<Badge tone="red">Sent to Ops Manager · incident prepared</Badge>}
        </div>
      </div>)}
    </div>
  </Screen>;
}

function QRBlock({size=180}){
  const cells=[];const n=21;
  const rand=(x,y)=>((x*73856093)^(y*19349663))%97<44;
  const inEye=(x,y)=>((x<7&&y<7)||(x>=n-7&&y<7)||(x<7&&y>=n-7));
  for(let y=0;y<n;y++)for(let x=0;x<n;x++){if(inEye(x,y))continue;if(rand(x,y))cells.push(<rect key={x+'-'+y} x={x} y={y} width="1" height="1"/>);}
  const eye=(ox,oy)=><g key={ox+''+oy}><rect x={ox} y={oy} width="7" height="7" fill="none" stroke="currentColor" strokeWidth="1"/><rect x={ox+2} y={oy+2} width="3" height="3"/></g>;
  return <svg width={size} height={size} viewBox={'-1 -1 '+(n+2)+' '+(n+2)} style={{color:'var(--cnc-charcoal)',display:'block'}} fill="currentColor" shapeRendering="crispEdges">{cells}{eye(0,0)}{eye(n-7,0)}{eye(0,n-7)}</svg>;
}

function Stars({value,onChange,size=30}){
  return <div style={{display:'flex',gap:6}}>
    {[1,2,3,4,5].map(n=><button key={n} onClick={()=>onChange(n)} aria-label={n+' stars'} style={{border:'none',background:'none',cursor:'pointer',padding:2,display:'flex'}}>
      <svg width={size} height={size} viewBox="0 0 24 24" fill={n<=value?'#FFB81C':'none'} stroke={n<=value?'#FFB81C':'#C9C9C9'} strokeWidth="1.6" strokeLinejoin="round" style={{transition:'fill 120ms, transform 120ms',transform:n===value?'scale(1.12)':'none'}}><path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.5L12 17.3l-5.9 3.2 1.3-6.5L2.5 9.4l6.6-.8L12 2.5z"/></svg>
    </button>)}
  </div>;
}

function ClientSurveyScreen({onBack,onDone}){
  const qs=[
    {k:'staff',t:'Our staff member',s:'Friendliness, knowledge and helpfulness, with emotional intelligence'},
    {k:'hygiene',t:'Personal hygiene of our staff member',s:'Presentation and cleanliness'},
    {k:'unit',t:'Cleanliness and hygiene of the unit and equipment',s:'The testing station, instruments and consumables'},
    {k:'overall',t:'Your overall experience of Care Net Consultants',s:'From arrival to done'},
  ];
  const [r,setR]=React.useState({});
  const [step,setStep]=React.useState(0); // 0 survey, 1 google
  const [copied,setCopied]=React.useState(false);
  const [nameOk,setNameOk]=React.useState(false);
  const [cName,setCName]=React.useState('');
  const done=qs.every(q=>r[q.k]);
  const avg=done?((r.staff+r.hygiene+r.unit+r.overall)/4):0;
  const summary='Professional occupational health testing by Care Net Consultants at our site today. '+(avg>=4.5?'Outstanding service':avg>=3.5?'Friendly, knowledgeable service':'Service')+' from Thandi Mokoena, a clean and well prepared mobile unit, and the whole process was quick and respectful. Recommended.'+(nameOk&&cName?' Review by '+cName+'.':'');
  if(step===1) return <div style={{display:'flex',flexDirection:'column',height:'100%',background:'#fff'}}>
    <AppBar onBack={()=>setStep(0)} title="Thank you"/>
    <div className="cnc-scroll" style={{flex:1,overflow:'auto',overflowX:'hidden',padding:20,display:'flex',flexDirection:'column',gap:14}}>
      <div style={{display:'flex',gap:4,justifyContent:'center',paddingTop:6}}>{[1,2,3,4,5].map(n=><svg key={n} width="26" height="26" viewBox="0 0 24 24" fill={n<=Math.round(avg)?'#FFB81C':'none'} stroke="#FFB81C" strokeWidth="1.6"><path d="M12 2.5l2.9 6.1 6.6.8-4.9 4.6 1.3 6.5L12 17.3l-5.9 3.2 1.3-6.5L2.5 9.4l6.6-.8L12 2.5z"/></svg>)}</div>
      <div style={{fontFamily:'var(--font-display)',fontSize:26,letterSpacing:'.02em',textAlign:'center'}}>Thank you for your feedback</div>
      <div style={{fontSize:13,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5}}>Your words carry further than you think. A short Google review helps other companies choose safe, dignified testing for their people, and it lands on the desk of the team who looked after you today. We wrote a first draft from your stars, ready to copy and paste.</div>
      <div style={{background:'var(--surface-panel)',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 15px',fontSize:13.5,lineHeight:1.6,fontStyle:'italic'}}>{summary}</div>
      <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px',display:'flex',flexDirection:'column',gap:10,textAlign:'left'}}>
        <Checkbox label="I am happy to put my name next to this review" checked={nameOk} onChange={()=>setNameOk(!nameOk)}/>
        {nameOk&&<React.Fragment>
          <Input label="Name and surname" placeholder="Your name as it should appear" value={cName} onChange={e=>setCName(e.target.value)}/>
          <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.5}}>POPIA consent: by adding your name you consent to Care Net Consultants storing it with this feedback and showing it beside the review. Nothing else about you is collected, and you may ask for it to be removed at any time.</div>
        </React.Fragment>}
      </div>
      <div style={{fontSize:11.5,color:'var(--text-muted)',textAlign:'center'}}>Naming Thandi Mokoena keeps the review genuine. Please post it from your own Google account.</div>
      <Button size="lg" style={{width:'100%',justifyContent:'center'}} onClick={()=>{try{navigator.clipboard.writeText(summary);}catch(e){}setCopied(true);}}>{copied?'Copied. Opening Google…':'Copy summary and open Google review'}</Button>
      {copied&&<div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5}}>Google My Business · Care Net Consultants Midrand<br/><a href={window.CNC.gmb['Midrand']} target="_blank" style={{fontFamily:'var(--font-heading)',fontWeight:600}}>{window.CNC.gmb['Midrand']}</a></div>}
      <button onClick={()=>onDone(avg)} style={{border:'none',background:'none',color:'var(--text-muted)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer',padding:8}}>Finish</button>
    </div>
    <div style={{height:10,background:'url(assets/pattern-band-4k.png) repeat-x',backgroundSize:'auto 100%',flex:'none'}}></div>
  </div>;
  return <div style={{display:'flex',flexDirection:'column',height:'100%',background:'#fff'}}>
    <AppBar onBack={onBack} title="Quick survey · under a minute"/>
    <div className="cnc-scroll" style={{flex:1,overflow:'auto',overflowX:'hidden',padding:20,display:'flex',flexDirection:'column',gap:16}}>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:19,lineHeight:1.3}}>How was your occupational health testing today?</div>
      <div style={{display:'flex',alignItems:'center',gap:10,background:'var(--surface-panel)',borderRadius:'var(--radius-pill)',padding:'6px 14px 6px 6px',alignSelf:'flex-start'}}>
        <FramedAvatar size={34}/>
        <span style={{fontSize:12.5}}>You were looked after by <strong style={{fontFamily:'var(--font-heading)',fontWeight:700}}>Thandi Mokoena</strong></span>
      </div>
      <div style={{fontSize:13,color:'var(--text-muted)',lineHeight:1.55,marginTop:-8}}>Your voice shapes how this team cares for the next workplace. Three quick stars, under a minute.</div>
      {qs.map(q=><div key={q.k} style={{background:'var(--surface-panel)',borderRadius:'var(--radius-md)',padding:'14px 16px'}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>{q.t}</div>
        <div style={{fontSize:12,color:'var(--text-muted)',marginTop:2,marginBottom:10}}>{q.s}</div>
        <Stars value={r[q.k]||0} onChange={v=>setR({...r,[q.k]:v})}/>
      </div>)}
      <Button size="lg" style={{width:'100%',justifyContent:'center'}} disabled={!done} onClick={()=>setStep(1)}>Submit feedback</Button>
      <div style={{fontSize:11.5,color:'var(--text-muted)',textAlign:'center'}}>Your feedback goes to Care Net Consultants management. No personal information is collected.</div>
    </div>
  </div>;
}

function SurveyScreen({onBack,nav,toast,wallet,addAmount}){
  const [survey,setSurvey]=React.useState(false);
  const settle=avg=>{
    setSurvey(false);
    if(avg<3){toast(avg.toFixed(1)+' stars. Sent to the Operations Manager and an incident report has been prepared for management. No payout.');}
    else if(avg<4){toast(avg.toFixed(1)+' stars logged. Only 4 and 5 star reviews earn the team split.');}
    else{addAmount(2);toast(avg.toFixed(1)+' stars. R6 team split: R2 added to each of the 3 team wallets.');}
  };
  if(survey) return <ClientSurveyScreen onBack={()=>setSurvey(false)} onDone={settle}/>;
  return <Screen pad bar={<AppBar onBack={onBack} title="Client survey"/>} nav={nav}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>Ask your client to scan</div>
    <div style={{fontSize:13,color:'var(--text-muted)',lineHeight:1.55,marginTop:-6}}>Most clients are happy to help when the moment is right. Ask just after their people are done, while the care is still fresh. One survey per jobcard: a 4 or 5 star review earns R6, split equally across the team. Below 3 stars goes straight to the Operations Manager with an incident report prepared.</div>
    <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-lg)',padding:22,display:'flex',flexDirection:'column',alignItems:'center',gap:12,boxShadow:'var(--shadow-card)'}}>
      <QRBlock/>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13}}>Murray & Dickson · MS038605</div>
      <div style={{fontSize:11.5,color:'var(--text-muted)'}}>Served by Thandi Mokoena · Google listing: Care Net Consultants Midrand</div>
      <Pulse height={18}/>
    </div>
    <Button size="lg" style={{width:'100%',justifyContent:'center'}} onClick={()=>setSurvey(true)}>Open the survey on this device</Button>
    <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5,padding:'0 10px'}}>Hand the device to your client, or let them scan with their own phone. Your rewards are private and live in your profile.</div>
  </Screen>;
}

function WalletScreen({onBack,nav,wallet}){
  return <Screen pad bar={<AppBar onBack={onBack} title="My wallet"/>} nav={nav}>
    <div style={{background:'var(--cnc-charcoal)',color:'#fff',borderRadius:'var(--radius-md)',padding:'20px 18px'}}>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11,letterSpacing:'.08em',textTransform:'uppercase',opacity:.65}}>Review rewards balance</div>
      <div style={{fontFamily:'var(--font-display)',fontSize:44,letterSpacing:'.02em',lineHeight:1.1,fontVariantNumeric:'tabular-nums',marginTop:4}}>R {wallet}</div>
      <Pulse white height={20} style={{marginTop:10}}/>
      <div style={{fontSize:12,opacity:.8,marginTop:8}}>R6 for every 4 or 5 star survey and Google review, split equally across the jobcard team. One review per jobcard. Below 3 stars pays nothing and goes to the Operations Manager.</div>
    </div>
    <SectionLabel>Review leaders · August</SectionLabel>
    <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px',display:'flex',flexDirection:'column',gap:10}}>
      {window.CNC.reviewLeaders.map((l,i)=><div key={l.name} style={{display:'flex',alignItems:'center',gap:12}}>
        <span style={{width:26,height:26,borderRadius:'50%',background:i===0?'#FFB81C':i===1?'#D8D8D8':'#E3B27C',color:'#1E1E1E',display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--font-heading)',fontWeight:800,fontSize:12,flex:'none'}}>{i+1}</span>
        <span style={{flex:1,fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5}}>{l.name}</span>
        <span style={{fontSize:12.5,color:'var(--text-muted)',fontVariantNumeric:'tabular-nums'}}>{l.count} reviews</span>
      </div>)}
      <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.5}}>The top three each month earn a badge on their employee profile.</div>
    </div>
    <SectionLabel>Earned</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:8}}>
      {window.CNC.wallet.events.map((e,i)=><div key={i} style={{display:'flex',alignItems:'center',gap:12,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'11px 14px'}}>
        <span style={{width:32,height:32,borderRadius:'50%',background:e.amount>0?'var(--green-tint)':'var(--red-tint)',color:e.amount>0?'var(--cnc-green)':'var(--cnc-red)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n={e.amount>0?'check':'alert'} size={15}/></span>
        <div style={{flex:1,minWidth:0}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13}}>{e.client}</div>
          <div style={{fontSize:11.5,color:'var(--text-muted)',marginTop:1}}>{e.what} · {e.at}</div>
        </div>
        <span style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:14,color:e.amount>0?'var(--cnc-green)':'var(--text-muted)',fontVariantNumeric:'tabular-nums'}}>{e.amount>0?'+R'+e.amount:'R0'}</span>
      </div>)}
    </div>
  </Screen>;
}
function ProfileScreen({onBack,nav,toast,onWallet,wallet}){
  const [edit,setEdit]=React.useState(false);
  const [cam,setCam]=React.useState(false);
  const [photoAt,setPhotoAt]=React.useState('12/01/2026');
  const [f,setF]=React.useState({first:'Thandi',last:'Mokoena',email:'t.mokoena@carenetconsultants.co.za',cell:'082 000 0142'});
  const set=k=>e=>setF({...f,[k]:e.target.value});
  return <Screen pad bar={<AppBar onBack={onBack} title="My details"/>} nav={nav}
    sticky={edit?<StickyBar><Button variant="secondary" onClick={()=>setEdit(false)}>Cancel</Button><Button style={{flex:1,justifyContent:'center'}} onClick={()=>{setEdit(false);toast('Details submitted for approval. A super user confirms changes to your record.');}}>Save changes</Button></StickyBar>:<StickyBar><Button style={{flex:1,justifyContent:'center'}} onClick={()=>setEdit(true)}>Edit my details</Button></StickyBar>}>
    {cam&&<CamView frameLabel="New reference photograph" torchable={false} onCancel={()=>setCam(false)} onCapture={()=>{setCam(false);setPhotoAt('06/08/2026');toast('New reference photograph submitted. It becomes active once a super user approves it.');}}/>}
    <div style={{display:'flex',alignItems:'center',gap:14,padding:'6px 2px'}}>
      <FramedAvatar name={f.first+' '+f.last} size={72}/>
      <div>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:17}}>{f.first} {f.last}</div>
        <div style={{fontSize:12.5,color:'var(--text-muted)'}}>CNC0142 · OHS practitioner · Normal user</div>
        <div style={{marginTop:6}}><Badge tone="yellow">Top 3 reviewer · July</Badge></div>
      </div>
    </div>
    <button onClick={onWallet} style={{display:'flex',alignItems:'center',gap:12,background:'var(--cnc-charcoal)',color:'#fff',border:'none',borderRadius:'var(--radius-md)',padding:'14px 16px',cursor:'pointer',textAlign:'left',width:'100%'}}>
      <div style={{flex:1}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11,letterSpacing:'.07em',textTransform:'uppercase',opacity:.65}}>My review wallet · private to you</div>
        <div style={{fontFamily:'var(--font-display)',fontSize:28,letterSpacing:'.02em',lineHeight:1.1,fontVariantNumeric:'tabular-nums'}}>R {wallet}</div>
      </div>
      <I n="chevR" size={18}/>
    </button>
    <SectionLabel>Personal details</SectionLabel>
    {edit?<React.Fragment>
      <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10}}>
        <Input label="First name" value={f.first} onChange={set('first')}/>
        <Input label="Surname" value={f.last} onChange={set('last')}/>
      </div>
      <Input label="Work email" value={f.email} onChange={set('email')}/>
      <Input label="Cell number" value={f.cell} onChange={set('cell')}/>
    </React.Fragment>
    :<Card><div style={{display:'flex',flexDirection:'column',gap:8,fontSize:13.5}}>
      {[['Employee number','CNC0142'],['Work email',f.email],['Cell number',f.cell],['Home unit','Midrand Clinic'],['Role','OHS practitioner']].map(([k,v])=>
      <div key={k} style={{display:'flex',gap:12}}><span style={{width:118,color:'var(--text-muted)',flex:'none'}}>{k}</span><strong style={{fontWeight:600,minWidth:0,overflowWrap:'anywhere'}}>{v}</strong></div>)}
    </div></Card>}
    <SectionLabel>Employee file · CV, FICA and documents</SectionLabel>
    <EmployeeFilePanel toast={toast}/>
    <SectionLabel>Reference photograph</SectionLabel>
    <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px',display:'flex',alignItems:'center',gap:12}}>
      <span style={{width:40,height:40,borderRadius:'50%',background:'var(--surface-panel)',color:'var(--text-muted)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n="camera" size={18}/></span>
      <div style={{flex:1,minWidth:0}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5}}>On file since {photoAt}</div>
        <div style={{fontSize:12,color:'var(--text-muted)',marginTop:2}}>Used only to verify it is you when clocking in</div>
      </div>
      <Button size="sm" variant="secondary" onClick={()=>setCam(true)}>Retake</Button>
    </div>
    <SectionLabel>Sign in and verification</SectionLabel>
    <SecurityPanel toast={toast}/>
    <SectionLabel>POPIA consent</SectionLabel>
    <ConsentPanel toast={toast}/>
    <div style={{fontSize:12,color:'var(--text-muted)',lineHeight:1.5,textAlign:'center',padding:'0 12px'}}>Changes to your details and photograph take effect once approved by a super user. You may withdraw consent at any time.</div>
  </Screen>;
}

function ConsentPanel({toast}){
  const initial=[
    {k:'emp',t:'Employment processing',s:'Your personal information used for HR, payroll, leave and statutory reporting. Required for your employment.',given:'12/01/2026',on:true,locked:true},
    {k:'bio',t:'Biometric verification',s:'Your reference photograph used to verify it is you when clocking in. Special personal information under POPIA.',given:'12/01/2026',on:true},
    {k:'health',t:'Occupational health records',s:'Your own medical surveillance records processed for OHS Act and COIDA compliance.',given:'12/01/2026',on:true},
    {k:'social',t:'Social media',s:'Photographs or videos of you on Care Net social media pages.',given:null,on:false},
    {k:'ads',t:'Online advertising and marketing',s:'Your image or name in online advertising, the website or marketing material.',given:null,on:false},
    {k:'news',t:'Internal newsletters',s:'Your name and photograph in Care Net Connect and internal communications.',given:'12/01/2026',on:true},
  ];
  const [cs,setCs]=React.useState(initial);
  const [open,setOpen]=React.useState(false);
  const flip=k=>{
    setCs(cs.map(c=>c.k===k?{...c,on:!c.on,given:!c.on?'06/08/2026':c.given}:c));
    const c=cs.find(x=>x.k===k);
    toast(c.on?'Consent withdrawn: '+c.t+'. Logged with the Information Officer.':'Consent given: '+c.t+'. Logged with the Information Officer.');
  };
  return <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',overflow:'hidden'}}>
    <button onClick={()=>setOpen(!open)} style={{display:'flex',alignItems:'center',gap:10,width:'100%',textAlign:'left',border:'none',background:'none',padding:'13px 14px',cursor:'pointer',minHeight:48}}>
      <span style={{color:'var(--cnc-red)',display:'flex',flex:'none'}}><I n="shield" size={19}/></span>
      <span style={{flex:1}}>
        <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13.5}}>Manage my consents</span>
        <span style={{display:'block',fontSize:12,color:'var(--text-muted)',marginTop:2}}>{cs.filter(c=>c.on).length} of {cs.length} given · add or revoke at any time</span>
      </span>
      <span style={{color:'var(--text-muted)',display:'flex',transform:open?'rotate(90deg)':'none',transition:'transform var(--dur-fast)'}}><I n="chevR" size={18}/></span>
    </button>
    {open&&<div style={{borderTop:'1px solid var(--border-subtle)',padding:'6px 14px 12px',display:'flex',flexDirection:'column'}}>
      {cs.map((c,i)=><div key={c.k} style={{display:'flex',gap:12,alignItems:'flex-start',padding:'11px 0',borderTop:i>0?'1px solid var(--surface-panel)':'none'}}>
        <input type="checkbox" checked={c.on} disabled={c.locked} onChange={()=>flip(c.k)} style={{accentColor:'var(--cnc-red)',width:19,height:19,marginTop:2,flex:'none',cursor:c.locked?'not-allowed':'pointer'}}/>
        <div style={{flex:1,minWidth:0}}>
          <div style={{display:'flex',gap:8,alignItems:'center'}}>
            <span style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13}}>{c.t}</span>
            {c.locked&&<Badge>Required</Badge>}
          </div>
          <div style={{fontSize:12,color:'var(--text-muted)',lineHeight:1.45,marginTop:2}}>{c.s}</div>
          <div style={{fontSize:11,color:c.on?'var(--cnc-green)':'var(--text-muted)',marginTop:3,fontFamily:'var(--font-heading)',fontWeight:600}}>{c.on?'Given '+c.given:'Not given'}</div>
        </div>
      </div>)}
      <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.5,paddingTop:8,borderTop:'1px solid var(--surface-panel)'}}>Every change is dated, logged and confirmed by the Information Officer. Withdrawing a consent stops future use; it does not affect processing that was lawful while consent stood.</div>
    </div>}
  </div>;
}

function SecurityPanel({toast}){
  const [open,setOpen]=React.useState(true);
  const [face,setFace]=React.useState(true);
  const [finger,setFinger]=React.useState(false);
  const [sms,setSms]=React.useState(true);
  const [totp,setTotp]=React.useState(false);
  const [cam,setCam]=React.useState(false);
  const [scan,setScan]=React.useState(false);
  React.useEffect(()=>{if(scan){const t=setTimeout(()=>{setScan(false);setFinger(true);toast('Fingerprint enrolled on the external scanner. Template stays on the device, never in the cloud.');},2200);return()=>clearTimeout(t);}},[scan]);
  const Row=({icon,title,sub,on,action,onAction})=><div style={{display:'flex',gap:12,alignItems:'center',padding:'12px 0',borderTop:'1px solid var(--surface-panel)'}}>
    <span style={{width:36,height:36,borderRadius:'50%',background:on?'var(--green-tint)':'var(--surface-panel)',color:on?'var(--cnc-green)':'var(--text-muted)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n={icon} size={17}/></span>
    <div style={{flex:1,minWidth:0}}>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13}}>{title}</div>
      <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.45,marginTop:2}}>{sub}</div>
    </div>
    {on?<Badge tone="green">Active</Badge>:<Button size="sm" variant="secondary" onClick={onAction}>{action}</Button>}
  </div>;
  return <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',overflow:'hidden'}}>
    {cam&&<CamView frameLabel="Facial recognition enrolment" torchable={false} onCancel={()=>setCam(false)} onCapture={()=>{setCam(false);setFace(true);toast('Facial recognition updated against your reference photograph.');}}/>}
    {scan&&<div style={{position:'absolute',inset:0,background:'#101010',zIndex:6,display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:18,color:'#fff',padding:28,textAlign:'center'}}>
      <div style={{width:96,height:120,border:'2.5px solid var(--cnc-red)',borderRadius:48,display:'flex',alignItems:'center',justifyContent:'center',position:'relative',overflow:'hidden'}}>
        <svg width="56" height="72" viewBox="0 0 56 72" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" opacity=".85"><path d="M28 12c-12 0-20 9-20 20v8"/><path d="M28 20c-8 0-13 6-13 12v12"/><path d="M28 28c-4 0-6 3-6 6v16"/><path d="M28 36v22"/><path d="M35 30c1 2 1 4 1 6v14"/><path d="M41 26c2 3 2 6 2 10v8"/><path d="M48 32v8"/></svg>
        <div className="cnc-scanline" style={{position:'absolute',left:6,right:6,height:2,background:'var(--cnc-red)'}}></div>
      </div>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:15}}>Hold your finger on the scanner…</div>
      <button onClick={()=>setScan(false)} style={{border:'1.5px solid #fff',background:'transparent',color:'#fff',borderRadius:'var(--radius-sm)',padding:'10px 24px',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,cursor:'pointer'}}>Cancel</button>
    </div>}
    <button onClick={()=>setOpen(!open)} style={{display:'flex',alignItems:'center',gap:10,width:'100%',textAlign:'left',border:'none',background:'none',padding:'13px 14px',cursor:'pointer',minHeight:48}}>
      <span style={{color:'var(--cnc-red)',display:'flex',flex:'none'}}><I n="user" size={19}/></span>
      <span style={{flex:1}}>
        <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13.5}}>Biometric and account protection</span>
        <span style={{display:'block',fontSize:12,color:'var(--text-muted)',marginTop:2}}>{[face,finger,sms,totp].filter(Boolean).length} of 4 methods active</span>
      </span>
      <span style={{color:'var(--text-muted)',display:'flex',transform:open?'rotate(90deg)':'none',transition:'transform var(--dur-fast)'}}><I n="chevR" size={18}/></span>
    </button>
    {open&&<div style={{padding:'0 14px 12px',display:'flex',flexDirection:'column'}}>
      <Row icon="camera" title="Facial recognition" sub="Matched against your reference photograph when you clock in or start a jobcard" on={face} action="Enrol" onAction={()=>setCam(true)}/>
      <Row icon="gps" title="Fingerprint scanning" sub="External enrolled scanner on the unit device. Template never leaves the scanner." on={finger} action="Enrol" onAction={()=>setScan(true)}/>
      <Row icon="mail" title="SMS fallback" sub="A code to 082 000 0142 if you lose your password or authenticator" on={sms} action="Set up" onAction={()=>{setSms(true);toast('Test code sent to 082 000 0142. SMS fallback active.');}}/>
      <Row icon="shield" title="Authenticator app" sub="Time based codes for two step sign in. Strongest protection." on={totp} action="Link app" onAction={()=>{setTotp(true);toast('Authenticator linked. Setup key CNC-0142-7K2M scanned and confirmed.');}}/>
      <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.5,paddingTop:8,borderTop:'1px solid var(--surface-panel)'}}>Biometric methods need your biometric consent below. Templates are never stored in the cloud, only the reference photograph is kept, in a private store.</div>
    </div>}
  </div>;
}

function EmployeeFilePanel({toast}){
  const initialDocs=[
    {k:'sanc',t:'SANC registration',s:'South African Nursing Council',status:'Active',until:'31/12/2026',ok:true},
    {k:'sashon',t:'SASHON membership',s:'SA Society of Occupational Health Nursing',status:'Active',until:'28/02/2027',ok:true},
    {k:'qual',t:'Qualifications',s:'Certificates and training records',status:'3 on file',until:null,ok:true},
    {k:'lic',t:'Driving licence',s:'Code B · needed for site verification',status:'Expires 14/09/2026',until:null,ok:false},
    {k:'id',t:'ID document',s:'Certified copy for client site verification',status:'On file',until:null,ok:true},
  ];
  const [docs,setDocs]=React.useState(initialDocs);
  const [cam,setCam]=React.useState(null);
  return <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px',display:'flex',flexDirection:'column',gap:4}}>
    {cam&&<CamView frameLabel={'Upload: '+docs.find(d=>d.k===cam).t} onCancel={()=>setCam(null)} onCapture={()=>{setDocs(docs.map(d=>d.k===cam?{...d,status:'Updated 06/08/2026',ok:true}:d));toast(docs.find(d=>d.k===cam).t+' uploaded. HR will verify and file it.');setCam(null);}}/>}
    <div style={{display:'flex',gap:8,paddingBottom:10}}>
      <Button size="sm" style={{flex:1,justifyContent:'center'}} onClick={()=>toast('Your Care Net CV on file has been opened for editing. Changes go to HR for verification.')} icon={<I n="file" size={14}/>}>Edit my CV on file</Button>
      <Button size="sm" variant="secondary" style={{flex:1,justifyContent:'center'}} onClick={()=>toast('FICA change request opened. Upload proof of address or banking changes; HR confirms within 48 hours.')}>Change FICA details</Button>
    </div>
    {docs.map((d,i)=><div key={d.k} style={{display:'flex',gap:12,alignItems:'center',padding:'11px 0',borderTop:'1px solid var(--surface-panel)'}}>
      <span style={{width:34,height:34,borderRadius:'50%',background:d.ok?'var(--green-tint)':'var(--yellow-tint)',color:d.ok?'var(--cnc-green)':'#8a6100',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n="file" size={15}/></span>
      <div style={{flex:1,minWidth:0}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13}}>{d.t}</div>
        <div style={{fontSize:11.5,color:'var(--text-muted)',marginTop:1}}>{d.s}</div>
        <div style={{fontSize:11,marginTop:2,fontFamily:'var(--font-heading)',fontWeight:600,color:d.ok?'var(--cnc-green)':'#8a6100'}}>{d.status}{d.until?' · to '+d.until:''}</div>
      </div>
      <Button size="sm" variant="secondary" onClick={()=>setCam(d.k)}>Upload new</Button>
    </div>)}
    <div style={{fontSize:11.5,color:'var(--text-muted)',lineHeight:1.5,paddingTop:8,borderTop:'1px solid var(--surface-panel)'}}>Clients may require these for site verification. Keep them current; expiring documents raise a reminder 30 days ahead.</div>
  </div>;
}

Object.assign(window,{DayStart,JobcardScreen,JobcardHistory,SurveyScreen,WalletScreen,TomorrowCard,ProfileScreen,ConsentPanel,SecurityPanel,WelcomeSplash});
