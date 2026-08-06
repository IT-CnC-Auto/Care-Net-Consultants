// Quick approvals: connect to supervisor, sales or finance; responses come back via WhatsApp and are logged with response time
const WA_GREEN='#25D366';
function ConnectScreen({onBack,nav,toast}){
  const contacts=[
    {k:'ops',name:'Pieter Botha',role:'Operational Supervisor',scope:'Operations, equipment, staffing on this jobcard',online:true},
    {k:'sales',name:'Carla Venter',role:'Sales consultant · MS038605',scope:'Client scope, bookings, extra medicals on site',online:true},
    {k:'fin',name:'Thabo Mthethwa',role:'Finance',scope:'PO numbers, quotes, payment queries',online:false},
  ];
  const [sel,setSel]=React.useState('ops');
  const [kind,setKind]=React.useState('Approval');
  const [msg,setMsg]=React.useState('');
  const [urgent,setUrgent]=React.useState(true);
  const [thread,setThread]=React.useState([
    {id:1,to:'Carla Venter',kind:'Approval',msg:'Client asks to add 4 walk-in medicals to today\u2019s booking. Approve the extra count?',at:'07:41',status:'answered',reply:'Approved. Add the 4, I will amend the quote with the PO before noon.',replyAt:'07:45',mins:4},
    {id:2,to:'Thabo Mthethwa',kind:'Question',msg:'Mitek PO16333 covers the drug tests as well?',at:'Yesterday 14:02',status:'answered',reply:'Yes, tests are on the same PO line. Invoice will reflect it.',replyAt:'Yesterday 14:31',mins:29},
  ]);
  const send=()=>{
    const c=contacts.find(x=>x.k===sel);
    const id=Date.now();
    setThread(t=>[{id,to:c.name,kind,msg,at:'Now',status:'pending'},...t]);
    setMsg('');
    toast('Sent to '+c.name+' on WhatsApp. You will be notified the moment they respond.');
    setTimeout(()=>{
      setThread(t=>t.map(x=>x.id===id?{...x,status:'answered',reply:kind==='Approval'?'Approved, go ahead.':'Noted, thanks. Call me if it changes.',replyAt:'Now',mins:2}:x));
      toast(c.name+' responded via WhatsApp in 2 min. Logged to the jobcard.');
    },6000);
  };
  const c=contacts.find(x=>x.k===sel);
  return <Screen pad bar={<AppBar onBack={onBack} title="Quick approvals"/>} nav={nav}>
    <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:20}}>Connect to the right person</div>
    <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:-8,lineHeight:1.5}}>They respond straight from WhatsApp. The reply pushes into the app and the response time is logged.</div>
    <SectionLabel>Send to</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:8}}>
      {contacts.map(x=><button key={x.k} onClick={()=>setSel(x.k)} style={{display:'flex',alignItems:'center',gap:12,textAlign:'left',background:'#fff',border:sel===x.k?'1.5px solid var(--cnc-red)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'11px 14px',cursor:'pointer'}}>
        <span style={{position:'relative',flex:'none'}}>
          <Avatar name={x.name} size={38}/>
          <span style={{position:'absolute',right:-1,bottom:-1,width:11,height:11,borderRadius:'50%',background:x.online?WA_GREEN:'#C4C4C4',border:'2px solid #fff'}}></span>
        </span>
        <span style={{flex:1,minWidth:0}}>
          <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13.5}}>{x.name} <span style={{fontWeight:400,color:'var(--text-muted)'}}>· {x.role}</span></span>
          <span style={{display:'block',fontSize:11.5,color:'var(--text-muted)',marginTop:2}}>{x.scope}</span>
        </span>
      </button>)}
    </div>
    <SectionLabel>Your message</SectionLabel>
    <div style={{display:'flex',gap:6}}>
      {['Approval','Question','Comment'].map(k=><button key={k} onClick={()=>setKind(k)} style={{flex:1,minHeight:40,border:kind===k?'1.5px solid var(--cnc-charcoal)':'1px solid var(--border-subtle)',background:kind===k?'var(--surface-panel)':'#fff',borderRadius:'var(--radius-sm)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer'}}>{k}</button>)}
    </div>
    <Input textarea label={kind+' for '+c.name.split(' ')[0]} placeholder={kind==='Approval'?'What needs approving, and by when':'Keep it short and specific'} value={msg} onChange={e=>setMsg(e.target.value)}/>
    <Switch label="Urgent: needs an answer within 15 minutes" checked={urgent} onChange={()=>setUrgent(!urgent)}/>
    <Button size="lg" style={{width:'100%',justifyContent:'center'}} disabled={!msg} onClick={send} icon={<svg width="16" height="16" viewBox="0 0 24 24" fill="#fff"><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Zm5.2 13.8c-.2.6-1.3 1.2-1.8 1.2-.5.1-1 .2-3.4-.7-2.9-1.1-4.7-4-4.9-4.2-.1-.2-1.1-1.5-1.1-2.9s.7-2 1-2.3c.2-.3.5-.3.7-.3h.5c.2 0 .4 0 .6.5s.8 1.9.8 2c.1.1.1.3 0 .5-.3.6-.7.9-.5 1.2.7 1.2 1.6 2 2.8 2.6.3.2.5.1.7-.1l.9-1c.2-.3.4-.2.7-.1l2 1c.3.1.5.2.5.3.1.1.1.7-.2 1.3Z"/></svg>}>Send via WhatsApp</Button>
    <SectionLabel>Log · response times recorded</SectionLabel>
    <div style={{display:'flex',flexDirection:'column',gap:10}}>
      {thread.map(t=><div key={t.id} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'12px 14px'}}>
        <div style={{display:'flex',alignItems:'center',gap:8}}>
          <Badge tone={t.kind==='Approval'?'red':'blue'}>{t.kind}</Badge>
          <span style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:12.5,flex:1}}>To {t.to}</span>
          <span style={{fontSize:11,color:'var(--text-muted)'}}>{t.at}</span>
        </div>
        <div style={{fontSize:13,lineHeight:1.5,marginTop:6}}>{t.msg}</div>
        {t.status==='pending'?<div style={{display:'flex',alignItems:'center',gap:8,marginTop:10,fontSize:12,color:'var(--text-muted)'}}>
          <span style={{width:8,height:8,borderRadius:'50%',background:'#FFB81C',animation:'cncring 1.4s ease-out infinite'}}></span>Waiting for a WhatsApp response…
        </div>
        :<div style={{marginTop:10,background:'#E9F7EE',border:'1px solid rgba(37,211,102,.4)',borderRadius:'10px 10px 10px 2px',padding:'9px 12px'}}>
          <div style={{display:'flex',alignItems:'center',gap:6,fontSize:11,color:'var(--text-muted)'}}>
            <svg width="12" height="12" viewBox="0 0 24 24" fill={WA_GREEN}><path d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2Z"/></svg>
            Via WhatsApp · {t.replyAt} · <strong style={{color:'var(--cnc-green)'}}>responded in {t.mins} min</strong>
          </div>
          <div style={{fontSize:13,lineHeight:1.5,marginTop:4}}>{t.reply}</div>
        </div>}
      </div>)}
    </div>
  </Screen>;
}
Object.assign(window,{ConnectScreen});
