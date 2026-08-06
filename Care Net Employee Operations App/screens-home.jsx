// Home dashboard, Inspect hub, More menu
function HomeScreen({nav,go,pulseVariant}){
  const tasks=[
    {t:'Equipment inspection',s:'Audiometer CNC-AUD-0031',state:'done',time:'06:55'},
    {t:'Vehicle pre trip inspection',s:'LT 39 HN GP · Isuzu D-Max',state:'done',time:'06:38'},
    {t:'Daily calibration evidence',s:'3 devices on Trailer 1',state:'due'},
    {t:'Facility inspection',s:'Trailer 1 (TRN001), all stations',state:'due'},
    {t:'Equipment inspection',s:'Vision screener CNC-VIS-0009',state:'overdue'},
  ];
  const st={done:['var(--cnc-green)','var(--green-tint)','Done'],due:['var(--cnc-blue)','var(--blue-tint)','Due'],overdue:['var(--cnc-red)','var(--red-tint)','Overdue']};
  return <Screen pad bar={<AppBar title="Trailer 1 (TRN001)"/>} nav={nav}>
    <div>
      <div style={{fontFamily:'var(--font-display)',fontSize:30,letterSpacing:'.02em',lineHeight:1.05}}>Good morning, Thandi</div>
      <div style={{fontSize:13,color:'var(--text-muted)',marginTop:4}}>{window.CNC.today} · Jobcard MS038605 · Murray & Dickson</div>
    </div>
    <Pulse variant={pulseVariant} height={30}/>
    <button onClick={()=>go('clock')} style={{display:'flex',alignItems:'center',gap:12,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px',cursor:'pointer',textAlign:'left',boxShadow:'var(--shadow-card)'}}>
      <span style={{width:34,height:34,borderRadius:'50%',background:'var(--red-tint)',color:'var(--cnc-red)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n="clock" size={17}/></span>
      <span style={{flex:1}}>
        <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>Team clocking</span>
        <span style={{display:'block',fontSize:12,color:'var(--text-muted)',marginTop:2}}>2 of 3 on your jobcard clocked in</span>
      </span>
      <I n="chevR" size={18} style={{color:'var(--text-muted)'}}/>
    </button>
    <Banner tone="red" title="Vision screener set to do not use">Out of tolerance on this morning's slide verification. Do not test until a super user clears the device.</Banner>
    <div style={{display:'flex',alignItems:'baseline',gap:8}}>
      <SectionLabel>Your inspections · allocated assets only</SectionLabel>
      <span style={{fontSize:12,color:'var(--text-muted)',marginLeft:'auto'}}>2 of 5 done</span>
    </div>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {tasks.map((k,i)=>{const [c,bg,l]=st[k.state];
        return <button key={i} onClick={()=>k.state!=='done'&&go('inspect')} style={{display:'flex',alignItems:'center',gap:12,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px',cursor:k.state==='done'?'default':'pointer',textAlign:'left',boxShadow:'var(--shadow-card)',opacity:k.state==='done'?.72:1}}>
          <span style={{width:34,height:34,borderRadius:'50%',background:bg,color:c,display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n={k.state==='done'?'check':k.state==='overdue'?'alert':'clock'} size={17}/></span>
          <span style={{flex:1,minWidth:0}}>
            <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>{k.t}</span>
            <span style={{display:'block',fontSize:12,color:'var(--text-muted)',marginTop:2}}>{k.s}{k.time?' · '+k.time:''}</span>
          </span>
          <span style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:11,letterSpacing:'.06em',textTransform:'uppercase',color:c}}>{l}</span>
        </button>;})}
    </div>
    <SectionLabel>Your jobcard today</SectionLabel>
    <Card>
      <div style={{display:'flex',justifyContent:'space-around'}}>
        <BigNum v="2" label="Clocked in"/><BigNum v="74" label="Tests logged"/><BigNum v="1" label="Device blocked"/><BigNum v="2" label="Low stock"/>
      </div>
    </Card>
  </Screen>;
}

function InspectHub({nav,go}){
  return <Screen pad bar={<AppBar title="Inspections"/>} nav={nav}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>Start an inspection</div>
    <ListRow icon="inspect" title="Equipment inspection" sub="Scan the device barcode to begin" onClick={()=>go('scan')}/>
    <ListRow icon="building" title="Facility inspection" sub="Your allocated unit: Trailer 1 (TRN001)" onClick={()=>go('facility')}/>
    <ListRow icon="truck" title="Vehicle pre trip inspection" sub="Eight photographs, odometer, checklist" onClick={()=>go('vehicle')}/>
    <ListRow icon="flask" title="Daily calibration evidence" sub="Biological checks with photo proof" onClick={()=>go('scan-cal')}/>
    <SectionLabel>Submitted today</SectionLabel>
    <ListRow icon="check" title="Audiometer CNC-AUD-0031" sub="Passed · Thandi Mokoena, 06:55" right={<Badge tone="green">Pass</Badge>}/>
    <ListRow icon="check" title="LT 39 HN GP pre trip" sub="Passed · Johan van Wyk, 06:38" right={<Badge tone="green">Pass</Badge>}/>
    <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5,padding:'0 16px'}}>Submitted inspections are locked. Corrections are captured as new records that reference the original.</div>
  </Screen>;
}

function MoreScreen({nav,go,onLogout}){
  return <Screen pad bar={<AppBar title="More"/>} nav={nav}>
    <div style={{display:'flex',alignItems:'center',gap:14,padding:'6px 2px'}}>
      <FramedAvatar name="Thandi Mokoena" size={68}/>
      <div>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:17}}>Thandi Mokoena</div>
        <div style={{fontSize:12.5,color:'var(--text-muted)'}}>CNC0142 · OHS practitioner · Trailer 1 (TRN001)</div>
      </div>
    </div>
    <Pulse height={26}/>
    <SectionLabel>Reports</SectionLabel>
    <ListRow icon="speak" title="Quick approvals" sub="Reach your supervisor, sales or finance. They answer on WhatsApp." onClick={()=>go('connect')}/>
    <ListRow icon="alert" title="Report an incident" sub="Sent to HR, the Operations Manager and the Director" onClick={()=>go('incident')}/>
    <ListRow icon="speak" title="Speak Out" sub="Protected disclosure, identified or anonymous" onClick={()=>go('speakout')}/>
    <ListRow icon="clock" title="Team clocking" sub="Shared device roster for your unit" onClick={()=>go('clock')}/>
    <SectionLabel>My day</SectionLabel>
    <ListRow icon="file" title="My jobcard history" sub="Kept in your employee file for 12 months" onClick={()=>go('jobcard-history')}/>
    <ListRow icon="camera" title="Client survey and review" sub="A quick star survey and Google review for your client" onClick={()=>go('survey')}/>
    <SectionLabel>Company</SectionLabel>
    <ListRow icon="news" title="Newsletters" sub="The last twelve months of Care Net Connect" onClick={()=>go('news')}/>
    <ListRow icon="user" title="My details and consent" sub="Edit your details, reference photograph, POPIA choices" onClick={()=>go('profile')}/>
    <ListRow icon="logout" title="Sign out" danger onClick={onLogout} right={<span></span>}/>
    <div style={{marginTop:'auto',textAlign:'center',padding:'12px 0 4px'}}>
      <div style={{fontSize:12,color:'var(--text-muted)',fontStyle:'italic'}}>I am because we are.</div>
    </div>
  </Screen>;
}
Object.assign(window,{HomeScreen,InspectHub,MoreScreen});
