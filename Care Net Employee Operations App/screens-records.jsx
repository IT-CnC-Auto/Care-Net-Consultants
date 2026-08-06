// Modules 08–11: incident, Speak Out, newsletters, stock
function IncidentScreen({onBack,toast}){
  const [step,setStep]=React.useState(0);
  const [type,setType]=React.useState('Near miss');
  const [persons,setPersons]=React.useState([{role:'involved',name:'Sipho Dlamini'}]);
  const [photos,setPhotos]=React.useState(0);
  const [cam,setCam]=React.useState(false);
  const [desc,setDesc]=React.useState('');
  const [gen,setGen]=React.useState(false);
  const steps=['Details','Persons','Evidence','Review'];
  return <Screen pad bar={<AppBar onBack={step===0?onBack:()=>setStep(step-1)} title={'Incident report · '+steps[step]}/>}
    sticky={<StickyBar>
      {step<3?<Button size="lg" style={{flex:1,justifyContent:'center'}} onClick={()=>setStep(step+1)}>Continue</Button>
      :<Button size="lg" style={{flex:1,justifyContent:'center'}} onClick={()=>{setStep(4);toast('Incident submitted. Sent to HR, the Operations Manager and the Director.');}}>Submit incident report</Button>}
    </StickyBar>}>
    {cam&&<CamView frameLabel="Incident photograph" onCancel={()=>setCam(false)} onCapture={()=>{setPhotos(photos+1);setCam(false);}}/>}
    <div style={{display:'flex',gap:6}}>
      {steps.map((s,i)=><div key={s} style={{flex:1,height:4,borderRadius:2,background:i<=Math.min(step,3)?'var(--cnc-red)':'#fff'}}></div>)}
    </div>
    {step===0&&<React.Fragment>
      <SectionLabel>What happened</SectionLabel>
      <Select label="Incident type" options={window.CNC.incidentTypes} value={type} onChange={e=>setType(e.target.value)}/>
      <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10}}>
        <Input label="Date" value="06/08/2026" onChange={()=>{}}/>
        <Input label="Time" value="09:20" onChange={()=>{}}/>
      </div>
      <Select label="Site" options={['Zandvliet Colliery, client site','Mobile Unit 1','Cape Town Clinic']}/>
      <Input textarea label="Description" placeholder="What happened, in your own words" value={desc} onChange={e=>setDesc(e.target.value)}/>
      <Input textarea label="Immediate action taken" placeholder="What was done straight away"/>
      <Input label="Equipment involved (scan or type barcode)" placeholder="Optional"/>
    </React.Fragment>}
    {step===1&&<React.Fragment>
      <SectionLabel>Persons involved and witnesses</SectionLabel>
      {persons.map((p,i)=><div key={i} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px',display:'flex',flexDirection:'column',gap:10}}>
        <div style={{display:'flex',gap:8}}>
          {['involved','witness'].map(r=><button key={r} onClick={()=>setPersons(persons.map((x,j)=>j===i?{...x,role:r}:x))} style={{flex:1,minHeight:38,border:p.role===r?'1.5px solid var(--cnc-charcoal)':'1px solid var(--border-subtle)',background:p.role===r?'var(--surface-panel)':'#fff',borderRadius:'var(--radius-sm)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer',textTransform:'capitalize'}}>{r}</button>)}
        </div>
        <Input label="Full name" value={p.name} onChange={e=>setPersons(persons.map((x,j)=>j===i?{...x,name:e.target.value}:x))}/>
        <Input label="Contact" placeholder="Cell or email"/>
      </div>)}
      <Button variant="secondary" onClick={()=>setPersons([...persons,{role:'witness',name:''}])} icon={<I n="plus" size={15}/>}>Add another person</Button>
    </React.Fragment>}
    {step===2&&<React.Fragment>
      <SectionLabel>Photographs · {photos} attached</SectionLabel>
      <div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:8}}>
        {Array.from({length:photos}).map((_,i)=><PhotoTile key={i} label={'Photo '+(i+1)} taken onTake={()=>{}}/>)}
        <PhotoTile label="Add photograph" onTake={()=>setCam(true)}/>
      </div>
      <SectionLabel>Injuries</SectionLabel>
      <Select label="Injuries sustained" options={['None','First aid only','Medical treatment required','Reportable injury']}/>
    </React.Fragment>}
    {step===3&&<React.Fragment>
      <SectionLabel>Review before submitting</SectionLabel>
      <Card>
        <div style={{display:'flex',flexDirection:'column',gap:8,fontSize:13.5}}>
          {[['Type',type],['When','06/08/2026 at 09:20'],['Site','Zandvliet Colliery, client site'],['Persons',persons.map(p=>p.name||'Unnamed').join(', ')],['Photographs',photos+' attached'],['Reported by','Thandi Mokoena, CNC0142']].map(([k,v])=>
            <div key={k} style={{display:'flex',gap:12}}><span style={{width:96,color:'var(--text-muted)',flex:'none'}}>{k}</span><strong style={{fontWeight:600}}>{v}</strong></div>)}
        </div>
      </Card>
      <Banner tone="blue" icon="mail" title="Who is notified">HR, the Operations Manager and the Director receive this report immediately by push notification and email, as it is lodged.</Banner>
    </React.Fragment>}
    {step===4&&<React.Fragment>
      <div style={{display:'flex',flexDirection:'column',alignItems:'center',textAlign:'center',gap:12,padding:'22px 8px 6px'}}>
        <div style={{width:60,height:60,borderRadius:'50%',background:'var(--green-tint)',color:'var(--cnc-green)',display:'flex',alignItems:'center',justifyContent:'center'}}><I n="check" size={26}/></div>
        <div style={{fontFamily:'var(--font-display)',fontSize:28,letterSpacing:'.02em'}}>Incident IR-2026-0341 logged</div>
        <div style={{fontSize:13.5,color:'var(--text-muted)',maxWidth:280,lineHeight:1.55}}>The record is locked. The database remains the record of truth.</div>
      </div>
      <Button size="lg" style={{width:'100%',justifyContent:'center'}} onClick={()=>setGen(true)} icon={<I n="file" size={17}/>}>Generate statement</Button>
      <Banner tone="yellow" title="This is not yet an affidavit">The application prepares an affidavit ready statement in the prescribed format. It becomes an affidavit only once you sign it before a Commissioner of Oaths. That step happens in person, outside this application.</Banner>
      <Dialog open={gen} title="Statement generated" onClose={()=>setGen(false)} footer={<Button size="sm" onClick={()=>{setGen(false);onBack();}}>Done</Button>}>
        Statement IR-2026-0341-S1 has been saved as a PDF to the document register, with numbered paragraphs, deponent details and the attestation block left blank for the Commissioner of Oaths.
      </Dialog>
    </React.Fragment>}
  </Screen>;
}

function SpeakOutScreen({onBack}){
  const [anon,setAnon]=React.useState(true);
  const [sent,setSent]=React.useState(false);
  const [body,setBody]=React.useState('');
  if(sent) return <Screen pad bar={<AppBar onBack={onBack} title="Speak Out"/>}>
    <div style={{display:'flex',flexDirection:'column',alignItems:'center',textAlign:'center',gap:14,padding:'36px 12px'}}>
      <div style={{width:60,height:60,borderRadius:'50%',background:'var(--blue-tint)',color:'var(--cnc-blue)',display:'flex',alignItems:'center',justifyContent:'center'}}><I n="shield" size={26}/></div>
      <div style={{fontFamily:'var(--font-display)',fontSize:28,letterSpacing:'.02em'}}>Thank you for speaking out</div>
      <div style={{fontSize:13.5,color:'var(--text-muted)',maxWidth:290,lineHeight:1.55}}>Your reference code is below. Keep it safe. You can use it to check the status of your submission at any time, without signing in.</div>
      <div style={{background:'#fff',border:'1.5px dashed var(--cnc-charcoal)',borderRadius:'var(--radius-md)',padding:'14px 26px',fontFamily:'var(--font-heading)',fontWeight:800,fontSize:22,letterSpacing:'.12em'}}>SO-7K2M-D94Q</div>
      <div style={{fontSize:12.5,color:'var(--text-muted)',maxWidth:290,lineHeight:1.5}}>{anon?'No name, user id, device id or photograph was stored with this submission, and image location data was removed.':'Your submission is linked to your profile and visible only to the designated recipients.'}</div>
    </div>
  </Screen>;
  return <Screen pad bar={<AppBar onBack={onBack} title="Speak Out"/>}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={!body} onClick={()=>setSent(true)}>Submit securely</Button></StickyBar>}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>A safe way to raise a concern</div>
    <div style={{fontSize:13.5,color:'var(--text-muted)',lineHeight:1.55}}>This channel is protected under the Protected Disclosures Act. Your submission goes only to a small designated group outside line management. Managers cannot see it. The daily audit system never reads it.</div>
    <SectionLabel>How would you like to submit?</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      <button onClick={()=>setAnon(true)} style={{textAlign:'left',background:'#fff',border:anon?'1.5px solid var(--cnc-blue)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 15px',cursor:'pointer'}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14,color:anon?'var(--cnc-blue)':'var(--cnc-charcoal)'}}>Anonymously</div>
        <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:3,lineHeight:1.5}}>Nothing that identifies you is stored. Not your name, not this device, not any photograph data.</div>
      </button>
      <button onClick={()=>setAnon(false)} style={{textAlign:'left',background:'#fff',border:!anon?'1.5px solid var(--cnc-blue)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 15px',cursor:'pointer'}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14,color:!anon?'var(--cnc-blue)':'var(--cnc-charcoal)'}}>With my name</div>
        <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:3,lineHeight:1.5}}>The designated recipients can contact you directly. You are protected against any occupational detriment.</div>
      </button>
    </div>
    <Select label="What is this about?" options={['Safety concern','Ethics or conduct','Fraud or theft','Patient or worker dignity','Other']}/>
    <Input textarea label="Tell us what happened" placeholder="Take your time. The more detail, the better we can act." value={body} onChange={e=>setBody(e.target.value)}/>
  </Screen>;
}

function NewsScreen({onBack,nav}){
  return <Screen pad bar={<AppBar onBack={onBack} title="Newsletters"/>} nav={nav}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>Care Net Connect</div>
    <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:-8}}>The last twelve months, newest first</div>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {window.CNC.newsletters.map((n,i)=><button key={n.title} style={{display:'flex',gap:14,alignItems:'center',background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:12,cursor:'pointer',textAlign:'left'}}>
        <div style={{width:52,height:66,borderRadius:6,flex:'none',background:i%2?'var(--cnc-charcoal)':'var(--cnc-red)',display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:4,color:'#fff'}}>
          <Pulse still white height={12} style={{alignSelf:'center'}}/>
          <span style={{fontFamily:'var(--font-display)',fontSize:13,letterSpacing:'.04em'}}>{n.date.slice(3,5)}/{n.date.slice(8)}</span>
        </div>
        <span style={{flex:1,minWidth:0}}>
          <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>{n.title}</span>
          <span style={{display:'block',fontSize:12,color:'var(--text-muted)',marginTop:3}}>{n.date} · {n.pages} pages · PDF</span>
        </span>
        <I n="chevR" size={18} style={{color:'var(--text-muted)'}}/>
      </button>)}
    </div>
  </Screen>;
}

function StockScreen({nav,toast}){
  const [tab,setTab]=React.useState('Take stock');
  const [items,setItems]=React.useState(window.CNC.stock);
  const [sel,setSel]=React.useState(null);
  const [qty,setQty]=React.useState(1);
  const post=()=>{
    setItems(items.map(x=>x.id===sel.id?{...x,on_hand:tab==='Add stock'?x.on_hand+qty:Math.max(0,x.on_hand-qty)}:x));
    toast((tab==='Add stock'?'Added ':'Took ')+qty+' × '+sel.name+'. Movement logged, never editable.');
    setSel(null);setQty(1);
  };
  return <Screen pad bar={<AppBar title="Stock · Trailer 1 (TRN001)"/>} nav={nav}>
    <Tabs tabs={['Take stock','Add stock']} active={tab} onChange={setTab}/>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {items.map(it=>{const low=it.on_hand<it.min;
        return <button key={it.id} onClick={()=>setSel(it)} style={{display:'flex',alignItems:'center',gap:12,background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px',cursor:'pointer',textAlign:'left'}}>
          <span style={{flex:1,minWidth:0}}>
            <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:14}}>{it.name}</span>
            <span style={{display:'block',fontSize:12,color:'var(--text-muted)',marginTop:2}}>Minimum {it.min} {it.uom}</span>
          </span>
          {low&&<Badge tone="red">Low stock</Badge>}
          <span style={{fontFamily:'var(--font-display)',fontSize:24,letterSpacing:'.02em',fontVariantNumeric:'tabular-nums',color:low?'var(--cnc-red)':'var(--cnc-charcoal)',minWidth:34,textAlign:'right'}}>{it.on_hand}</span>
        </button>;})}
    </div>
    <SectionLabel>Recent movements</SectionLabel>
    <Card>
      <div style={{display:'flex',flexDirection:'column',gap:10}}>
        {window.CNC.movements.map((m,i)=><div key={i} style={{display:'flex',gap:10,alignItems:'center',fontSize:12.5}}>
          <Badge tone={m.type==='add'?'green':m.type==='correction'?'yellow':'red'}>{m.type==='add'?'+':m.type==='correction'?'±':'−'}{m.qty}</Badge>
          <span style={{flex:1}}>{m.item}</span>
          <span style={{color:'var(--text-muted)',flex:'none'}}>{m.by.split(' ')[0]} · {m.at}</span>
        </div>)}
      </div>
    </Card>
    <Dialog open={!!sel} title={sel?(tab==='Add stock'?'Add ':'Take ')+sel.name:''} onClose={()=>setSel(null)}
      footer={<React.Fragment><Button variant="secondary" size="sm" onClick={()=>setSel(null)}>Cancel</Button><Button size="sm" onClick={post}>{tab==='Add stock'?'Add stock':'Take stock'}</Button></React.Fragment>}>
      <div style={{display:'flex',alignItems:'center',justifyContent:'center',gap:18,padding:'8px 0'}}>
        <button onClick={()=>setQty(Math.max(1,qty-1))} aria-label="Less" style={{width:48,height:48,borderRadius:'50%',border:'1px solid var(--border-subtle)',background:'#fff',cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}><I n="minus" size={20}/></button>
        <div style={{fontFamily:'var(--font-display)',fontSize:44,letterSpacing:'.02em',minWidth:60,textAlign:'center',fontVariantNumeric:'tabular-nums'}}>{qty}</div>
        <button onClick={()=>setQty(qty+1)} aria-label="More" style={{width:48,height:48,borderRadius:'50%',border:'1px solid var(--border-subtle)',background:'var(--cnc-red)',color:'#fff',cursor:'pointer',display:'flex',alignItems:'center',justifyContent:'center'}}><I n="plus" size={20}/></button>
      </div>
      <div style={{fontSize:12.5,color:'var(--text-muted)',textAlign:'center'}}>Every movement records who, what, when and where. Movements are never edited or deleted.</div>
    </Dialog>
  </Screen>;
}
Object.assign(window,{IncidentScreen,SpeakOutScreen,NewsScreen,StockScreen});
