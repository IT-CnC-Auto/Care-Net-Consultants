// HR dashboard: sick leave, family responsibility leave, annual leave, SimplePay balances
const HR={annual:11,sick:24,family:3,decClosure:3,declinedMonths:['January','February','August','September','October']};
function HRScreen({onBack,nav,toast}){
  const [flow,setFlow]=React.useState(null); // sick | family | apply
  if(flow==='sick') return <SickLeaveFlow onBack={()=>setFlow(null)} nav={nav} toast={toast}/>;
  if(flow==='family') return <FamilyLeaveFlow onBack={()=>setFlow(null)} nav={nav} toast={toast}/>;
  if(flow==='apply') return <ApplyLeaveFlow onBack={()=>setFlow(null)} nav={nav} toast={toast}/>;
  return <Screen pad bar={<AppBar onBack={onBack} title="HR dashboard"/>} nav={nav}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>Leave and HR</div>
    <div style={{background:'var(--cnc-charcoal)',color:'#fff',borderRadius:'var(--radius-md)',padding:'16px 18px'}}>
      <div style={{display:'flex',alignItems:'baseline',gap:8}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11,letterSpacing:'.08em',textTransform:'uppercase',opacity:.65,flex:1}}>Leave days due to you</div>
        <span style={{fontSize:11,opacity:.6}}>via SimplePay</span>
      </div>
      <div style={{display:'flex',gap:22,marginTop:12}}>
        <div><div style={{fontFamily:'var(--font-display)',fontSize:34,letterSpacing:'.02em',lineHeight:1,fontVariantNumeric:'tabular-nums'}}>{HR.annual}</div><div style={{fontSize:11.5,opacity:.75,marginTop:3}}>Annual</div></div>
        <div><div style={{fontFamily:'var(--font-display)',fontSize:34,letterSpacing:'.02em',lineHeight:1,fontVariantNumeric:'tabular-nums'}}>{HR.sick}</div><div style={{fontSize:11.5,opacity:.75,marginTop:3}}>Sick (36 months)</div></div>
        <div><div style={{fontFamily:'var(--font-display)',fontSize:34,letterSpacing:'.02em',lineHeight:1,fontVariantNumeric:'tabular-nums'}}>{HR.family}</div><div style={{fontSize:11.5,opacity:.75,marginTop:3}}>Family resp.</div></div>
        <div><div style={{fontFamily:'var(--font-display)',fontSize:34,letterSpacing:'.02em',lineHeight:1,color:'var(--cnc-red)',fontVariantNumeric:'tabular-nums'}}>−{HR.decClosure}</div><div style={{fontSize:11.5,color:'var(--cnc-red)',marginTop:3}}>Dec closure</div></div>
      </div>
      <Pulse white height={18} style={{marginTop:12}}/>
      <div style={{fontSize:11.5,opacity:.75,marginTop:8,lineHeight:1.5}}>The December mandatory closure is reserved from your annual balance and cannot be taken as leave elsewhere in the year.</div>
      <button onClick={()=>toast('Opening your SimplePay employee profile…')} style={{border:'1px solid rgba(255,255,255,.35)',background:'transparent',color:'#fff',borderRadius:'var(--radius-sm)',padding:'8px 16px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer',marginTop:10}}>Open SimplePay</button>
    </div>
    <SectionLabel>Requests</SectionLabel>
    <ListRow icon="alert" title="Report sick leave" sub="Sick note compulsory on a Monday, Friday, or a day next to a public holiday" onClick={()=>setFlow('sick')}/>
    <ListRow icon="user" title="Family responsibility leave" sub="Upload proof of illness and your relationship" onClick={()=>setFlow('family')}/>
    <ListRow icon="clock" title="Apply for annual leave" sub="Some months are closed to leave unless a serious event" onClick={()=>setFlow('apply')}/>
    <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5,padding:'0 14px'}}>All requests go to HR for authorisation. You are notified of the outcome in the app and by email.</div>
  </Screen>;
}

function UploadTile({label,taken,onTake}){
  return <PhotoTile wide label={taken?label+' uploaded':label} taken={taken} onTake={onTake}/>;
}

function SickLeaveFlow({onBack,nav,toast}){
  const dates=[
    {d:'Thursday 6 August 2026',rule:null},
    {d:'Friday 7 August 2026',rule:'a Friday'},
    {d:'Monday 10 August 2026',rule:'a Monday, and the day after National Women\u2019s Day'},
    {d:'Tuesday 11 August 2026',rule:'the day after a public holiday'},
  ];
  const [sel,setSel]=React.useState(0);
  const [note,setNote]=React.useState(false);
  const [cam,setCam]=React.useState(false);
  const needNote=!!dates[sel].rule;
  return <Screen pad bar={<AppBar onBack={onBack} title="Report sick leave"/>} nav={nav}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={needNote&&!note} onClick={()=>{toast('Sick leave reported. HR has been notified'+(note?' with your sick note.':'.'));onBack();}}>Submit to HR</Button></StickyBar>}>
    {cam&&<CamView frameLabel="Photograph your sick note" onCancel={()=>setCam(false)} onCapture={()=>{setNote(true);setCam(false);}}/>}
    <SectionLabel>First day of sick leave</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:8}}>
      {dates.map((x,i)=><button key={x.d} onClick={()=>setSel(i)} style={{textAlign:'left',background:'#fff',border:sel===i?'1.5px solid var(--cnc-red)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px',cursor:'pointer',display:'flex',alignItems:'center',gap:10}}>
        <span style={{flex:1,fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5}}>{x.d}</span>
        {x.rule&&<Badge tone="yellow">Sick note required</Badge>}
      </button>)}
    </div>
    {needNote?<Banner tone="yellow" icon="alert" title="Sick note compulsory">Your selected date is {dates[sel].rule}. A sick note must be uploaded before this request can be submitted.</Banner>
    :<Banner tone="blue" icon="file" title="No sick note needed for this date">A sick note is only compulsory when the day is a Monday, a Friday, or the day before or after a public holiday, or from the second consecutive day.</Banner>}
    <SectionLabel>Sick note {needNote?'':'(optional)'}</SectionLabel>
    <UploadTile label="Upload or photograph your sick note" taken={note} onTake={()=>setCam(true)}/>
    <Input textarea label="Note to HR (optional)" placeholder="Anything HR should know"/>
  </Screen>;
}

function FamilyLeaveFlow({onBack,nav,toast}){
  const [p1,setP1]=React.useState(false);
  const [p2,setP2]=React.useState(false);
  const [cam,setCam]=React.useState(null);
  return <Screen pad bar={<AppBar onBack={onBack} title="Family responsibility leave"/>} nav={nav}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={!(p1&&p2)} onClick={()=>{toast('Family responsibility leave submitted to HR with both proofs.');onBack();}}>Submit to HR</Button></StickyBar>}>
    {cam&&<CamView frameLabel={cam===1?'Proof of illness':'Proof of relationship'} onCancel={()=>setCam(null)} onCapture={()=>{cam===1?setP1(true):setP2(true);setCam(null);}}/>}
    <Select label="Reason" options={['Child is ill','Spouse or partner is ill','Death in the immediate family','Birth of my child']}/>
    <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10}}>
      <Input label="First day" value="06/08/2026" onChange={()=>{}}/>
      <Input label="Days" value="1" onChange={()=>{}}/>
    </div>
    <Input label="Family member's name" placeholder="Full name"/>
    <Banner tone="blue" icon="file" title="Two documents are required">Upload the family member's proof of illness (or the relevant certificate) and proof of your relationship to them.</Banner>
    <SectionLabel>Required documents</SectionLabel>
    <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:8}}>
      <UploadTile label="Proof of illness" taken={p1} onTake={()=>setCam(1)}/>
      <UploadTile label="Proof of relationship" taken={p2} onTake={()=>setCam(2)}/>
    </div>
    <div style={{fontSize:12,color:'var(--text-muted)',lineHeight:1.5}}>You have {HR.family} family responsibility days left this cycle.</div>
  </Screen>;
}

function ApplyLeaveFlow({onBack,nav,toast}){
  const months=['January','February','March','April','May','June','July','August','September','October','November','December'];
  const [m,setM]=React.useState('November');
  const [proof,setProof]=React.useState(false);
  const [cam,setCam]=React.useState(false);
  const closed=HR.declinedMonths.includes(m);
  const dec=m==='December';
  const canSubmit=dec?false:(!closed||proof);
  return <Screen pad bar={<AppBar onBack={onBack} title="Apply for annual leave"/>} nav={nav}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={!canSubmit} onClick={()=>{toast(closed?'Request submitted with proof for special authorisation by HR and the Director.':'Leave request submitted to HR for authorisation.');onBack();}}>{closed?'Submit for special authorisation':'Submit to HR'}</Button></StickyBar>}>
    {cam&&<CamView frameLabel="Proof of serious event" onCancel={()=>setCam(false)} onCapture={()=>{setProof(true);setCam(false);}}/>}
    <SectionLabel>Month</SectionLabel>
    <div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:8}}>
      {months.map(x=>{const c=HR.declinedMonths.includes(x);const d=x==='December';
      return <button key={x} onClick={()=>setM(x)} style={{minHeight:44,border:m===x?'1.5px solid var(--cnc-red)':'1px solid var(--border-subtle)',background:d?'var(--red-tint)':c?'var(--surface-panel)':'#fff',color:d?'var(--cnc-red)':c?'var(--text-muted)':'var(--cnc-charcoal)',borderRadius:'var(--radius-sm)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer'}}>{x.slice(0,3)}{c&&!d?' ·':''}{d?' ✕':''}</button>;})}
    </div>
    <div style={{fontSize:11.5,color:'var(--text-muted)'}}>Months marked · are closed to leave. December is the mandatory closure, shown in red, and is booked automatically.</div>
    {dec&&<Banner tone="red" icon="x" title="December is the mandatory closure">The December closure is reserved from your balance automatically. You cannot apply for additional leave in December.</Banner>}
    {closed&&!dec&&<Banner tone="yellow" icon="alert" title={m+' is closed to leave'}>Leave in January, February, August, September and October is declined as standard due to operational demand. Only a serious event, with proof uploaded, goes to HR and the Director for special authorisation.</Banner>}
    {closed&&!dec&&<React.Fragment>
      <SectionLabel>Proof of serious event</SectionLabel>
      <UploadTile label="Upload proof for authorisation" taken={proof} onTake={()=>setCam(true)}/>
    </React.Fragment>}
    <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10}}>
      <Input label="First day" placeholder="DD/MM/YYYY"/>
      <Input label="Last day" placeholder="DD/MM/YYYY"/>
    </div>
    <Input textarea label="Reason" placeholder={closed?'Describe the serious event':'Optional'}/>
    <div style={{fontSize:12,color:'var(--text-muted)'}}>You have {HR.annual} annual leave days due, excluding the {HR.decClosure} days reserved for the December closure.</div>
  </Screen>;
}
Object.assign(window,{HRScreen});
