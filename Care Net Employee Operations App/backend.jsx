// Desktop web backend (Next.js on Vercel, admin surface)
function Backend({toast}){
  const [page,setPage]=React.useState('overview');
  const [pending,setPending]=React.useState(window.CNC.pendingUsers);
  const navItems=[['overview','Overview','home'],['jobcards','Daily jobcards','file'],['users','User management','user'],['config','Configuration','settings'],['devices','Device registry','inspect'],['reports','Agent reports','file']];
  return <div style={{display:'flex',height:'100%',background:'var(--surface-panel)',fontSize:14}}>
    <div style={{width:230,background:'var(--cnc-charcoal)',color:'#fff',display:'flex',flexDirection:'column',flex:'none'}}>
      <div style={{padding:'20px 18px 14px'}}>
        <img src="assets/logo-horizontal.png" alt="Care Net Consultants" style={{height:26,background:'#fff',borderRadius:6,padding:'5px 8px',width:'auto'}}/>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11,letterSpacing:'.08em',textTransform:'uppercase',opacity:.6,marginTop:12}}>Operations backend</div>
      </div>
      <div style={{display:'flex',flexDirection:'column',gap:2,padding:'0 10px'}}>
        {navItems.map(([k,l,ic])=><button key={k} onClick={()=>setPage(k)} style={{display:'flex',alignItems:'center',gap:10,border:'none',textAlign:'left',background:page===k?'var(--cnc-red)':'transparent',color:page===k?'#fff':'rgba(255,255,255,.75)',borderRadius:'var(--radius-sm)',padding:'10px 12px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13,cursor:'pointer'}}><I n={ic} size={17}/>{l}</button>)}
      </div>
      <div style={{marginTop:'auto',padding:16,borderTop:'1px solid rgba(255,255,255,.12)',display:'flex',alignItems:'center',gap:10}}>
        <Avatar name="Pieter Botha" size={34}/>
        <div style={{minWidth:0}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5}}>Pieter Botha</div>
          <div style={{fontSize:11,opacity:.6}}>Super user</div>
        </div>
      </div>
    </div>
    <div style={{flex:1,overflow:'auto',padding:'26px 30px',minWidth:0}}>
      {page==='overview'&&<BackendOverview goReports={()=>setPage('reports')}/>}
      {page==='jobcards'&&<BackendJobcards toast={toast}/>}
      {page==='users'&&<BackendUsers pending={pending} setPending={setPending} toast={toast}/>}
      {page==='config'&&<BackendConfig toast={toast}/>}
      {page==='devices'&&<BackendDevices/>}
      {page==='reports'&&<BackendReports/>}
    </div>
  </div>;
}

function PageTitle({title,sub,right}){
  return <div style={{display:'flex',alignItems:'flex-end',gap:16,marginBottom:20}}>
    <div style={{flex:1}}>
      <div style={{fontFamily:'var(--font-display)',fontSize:32,letterSpacing:'.02em',lineHeight:1}}>{title}</div>
      {sub&&<div style={{fontSize:13,color:'var(--text-muted)',marginTop:5}}>{sub}</div>}
    </div>
    {right}
  </div>;
}

function Th({children,right}){return <th style={{textAlign:right?'right':'left',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:11.5,letterSpacing:'.06em',textTransform:'uppercase',color:'var(--text-muted)',padding:'10px 14px',borderBottom:'1px solid var(--border-subtle)'}}>{children}</th>;}
function Td({children,right,strong}){return <td style={{textAlign:right?'right':'left',padding:'11px 14px',borderBottom:'1px solid var(--surface-panel)',fontSize:13.5,fontWeight:strong?600:400,fontVariantNumeric:'tabular-nums'}}>{children}</td>;}
function TableCard({children}){return <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',boxShadow:'var(--shadow-card)',overflow:'hidden'}}><table style={{width:'100%',borderCollapse:'collapse'}}>{children}</table></div>;}
const sevTone={high:'red',medium:'yellow',low:'green'};

function BackendOverview({goReports}){
  const r=window.CNC.agentReport;
  return <div style={{maxWidth:980}}>
    <PageTitle title="Overview" sub={window.CNC.today+' · exceptions first'} right={<Badge tone="red">2 need a decision</Badge>}/>
    <div style={{background:'var(--cnc-charcoal)',color:'#fff',borderRadius:'var(--radius-md)',padding:'20px 22px',marginBottom:16}}>
      <div style={{display:'flex',alignItems:'center',gap:12}}>
        <div style={{flex:1}}>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11,letterSpacing:'.08em',textTransform:'uppercase',opacity:.6}}>Daily audit report · generated {r.generated}</div>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:17,marginTop:6,lineHeight:1.4}}>Two matters need a decision today: a blocked vision screener on Mobile Unit 1 and one flagged clock event awaiting review.</div>
        </div>
        <div style={{display:'flex',gap:8,flex:'none'}}>
          <Badge tone="red">{r.summary.high} high</Badge><Badge tone="yellow">{r.summary.medium} medium</Badge><Badge tone="green">{r.summary.low} low</Badge>
        </div>
      </div>
      <Pulse white height={22} style={{marginTop:14}}/>
      <button onClick={goReports} style={{border:'1px solid rgba(255,255,255,.35)',background:'transparent',color:'#fff',borderRadius:'var(--radius-sm)',padding:'8px 16px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,cursor:'pointer',marginTop:12}}>Read the full report</button>
    </div>
    <div style={{display:'grid',gridTemplateColumns:'repeat(4,1fr)',gap:12,marginBottom:16}}>
      {[['1','Missed inspection','Elandsfontein facility, yesterday'],['1','Flagged clock event','N. Khumalo, confidence 0.58'],['1','Device do not use','CNC-VIS-0009, out of tolerance'],['2','Stock lines below minimum','Mouthpieces, alcohol swabs']].map(([n,t,s])=>
      <div key={t} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',boxShadow:'var(--shadow-card)'}}>
        <div style={{fontFamily:'var(--font-display)',fontSize:34,letterSpacing:'.02em',lineHeight:1,color:'var(--cnc-red)'}}>{n}</div>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,marginTop:8}}>{t}</div>
        <div style={{fontSize:12,color:'var(--text-muted)',marginTop:3,lineHeight:1.45}}>{s}</div>
      </div>)}
    </div>
    <TableCard>
      <thead><tr><Th>Exception</Th><Th>Detail</Th><Th>Severity</Th><Th right>Action</Th></tr></thead>
      <tbody>
        {r.items.slice(0,4).map(it=><tr key={it.title}>
          <Td strong>{it.title}</Td>
          <Td><span style={{color:'var(--text-muted)'}}>{it.body.slice(0,86)}…</span></Td>
          <Td><Badge tone={sevTone[it.sev]}>{it.sev}</Badge></Td>
          <Td right><Button size="sm" variant="secondary">Review</Button></Td>
        </tr>)}
      </tbody>
    </TableCard>
  </div>;
}

function BackendJobcards({toast}){
  const [pushed,setPushed]=React.useState({MS038605:true,MS038607:true});
  return <div style={{maxWidth:980}}>
    <PageTitle title="Daily jobcards" sub="Imported from the daily operations summary and pushed to each allocated team member's app" right={<div style={{display:'flex',gap:8}}><Button size="sm" variant="secondary" onClick={()=>toast('Note sent. Allocated staff received a push notification.')}>Send note to team</Button><Button size="sm" onClick={()=>toast("Tomorrow's jobcards uploaded. Allocated staff notified to pack and prepare.")}>Upload next day</Button></div>}/>
    <div style={{display:'flex',flexDirection:'column',gap:14}}>
      {window.CNC.jobcards.map(jc=><div key={jc.ref} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',boxShadow:'var(--shadow-card)',padding:'18px 20px'}}>
        <div style={{display:'flex',alignItems:'center',gap:12}}>
          <div style={{flex:1}}>
            <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:15}}>{jc.ref} · {jc.client}</div>
            <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:3}}>{jc.branch} · {jc.asset} · {jc.vehicle} · {jc.booked} booked · {jc.office_time}, {jc.site_time}</div>
          </div>
          {jc.travel&&<Badge tone="blue">Travel job</Badge>}
          {pushed[jc.ref]?<Badge tone="green">Pushed to Supabase</Badge>:<Button size="sm" onClick={()=>{setPushed({...pushed,[jc.ref]:true});toast(jc.ref+' pushed. Allocated staff will see it at day start.');}}>Push to app</Button>}
        </div>
        <div style={{display:'grid',gridTemplateColumns:'1fr 1fr 1fr',gap:'8px 16px',marginTop:12,fontSize:12.5}}>
          {[['Geofence',jc.geofence],['Start gate',jc.start+' · inside geofence only'],['Quote / PO',jc.quote+' · '+jc.po],['Address',jc.address+' · '+jc.distance],['Contact',jc.site_contact],['Medicals',jc.medicals]].map(([k,v])=>
          <div key={k}><div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:10.5,letterSpacing:'.07em',textTransform:'uppercase',color:'var(--text-muted)'}}>{k}</div><div style={{marginTop:2,lineHeight:1.45}}>{v}</div></div>)}
        </div>
        <div style={{display:'flex',gap:8,marginTop:12,flexWrap:'wrap'}}>
          {jc.team.map(t=><span key={t.name} style={{display:'inline-flex',alignItems:'center',gap:7,background:'var(--surface-panel)',borderRadius:'var(--radius-pill)',padding:'5px 12px 5px 6px',fontSize:12,fontFamily:'var(--font-heading)',fontWeight:600}}><Avatar name={t.name} size={22}/>{t.name}</span>)}
        </div>
      </div>)}
    </div>
    <div style={{marginTop:14}}>
      <Banner tone="blue" icon="gps" title="Geofenced day start">Staff cannot start a jobcard while travelling. Travel jobs use the guesthouse address as the geofence and open at the allocated start time. Each start writes the verification photo, GPS and geofence to Supabase.</Banner>
    </div>
  </div>;
}

function BackendUsers({pending,setPending,toast}){
  return <div style={{maxWidth:980}}>
    <PageTitle title="User management" sub="Pending registrations require super user approval before activation"/>
    {pending.length>0&&<div style={{marginBottom:18}}>
      <SectionLabel>Pending approval · {pending.length}</SectionLabel>
      <div style={{display:'flex',flexDirection:'column',gap:10,marginTop:10}}>
        {pending.map(u=><div key={u.emp} style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',display:'flex',alignItems:'center',gap:14,boxShadow:'var(--shadow-card)'}}>
          <Avatar name={u.name} size={40} tone="red"/>
          <div style={{flex:1,minWidth:0}}>
            <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>{u.name} <span style={{fontWeight:400,color:'var(--text-muted)'}}>· {u.emp}</span></div>
            <div style={{fontSize:12.5,color:'var(--text-muted)',marginTop:2}}>{u.email} · {u.unit} · submitted {u.submitted} · POPIA and biometric consent captured</div>
          </div>
          <select style={{border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-sm)',padding:'8px 10px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12.5,background:'#fff'}}>
            <option>Normal user</option><option>Super user</option><option>Viewer</option>
          </select>
          <Button size="sm" onClick={()=>{setPending(pending.filter(x=>x.emp!==u.emp));toast(u.name+' approved and activated.');}}>Approve</Button>
        </div>)}
      </div>
    </div>}
    <SectionLabel>Active users</SectionLabel>
    <div style={{marginTop:10}}>
    <TableCard>
      <thead><tr><Th>Name</Th><Th>Employee no</Th><Th>Unit</Th><Th>Role</Th><Th>Status</Th></tr></thead>
      <tbody>
        {window.CNC.roster.map(p=><tr key={p.id}>
          <Td strong>{p.first} {p.last}</Td><Td>{p.emp}</Td><Td>Mobile Unit 1</Td>
          <Td>{p.id==='p6'?'Super user':'Normal user'}</Td>
          <Td><Badge tone="green">Active</Badge></Td>
        </tr>)}
      </tbody>
    </TableCard>
    </div>
  </div>;
}

function BackendConfig({toast}){
  const [items,setItems]=React.useState(window.CNC.equipChecklist);
  return <div style={{maxWidth:980}}>
    <PageTitle title="Configuration" sub="Checklists, tolerances and lists are data. Changing them never needs a code deployment." right={<Button size="sm" onClick={()=>toast('New checklist version 4 published to all devices.')}>Publish version 4</Button>}/>
    <div style={{display:'flex',gap:8,marginBottom:16,flexWrap:'wrap'}}>
      {['Equipment checklists','Facility checklists','Vehicle checklists','Tolerance bands','Departments and units','Stock item master','Geofences','Notification lists'].map((t,i)=>
      <span key={t} style={{background:i===0?'var(--cnc-charcoal)':'#fff',color:i===0?'#fff':'var(--text-muted)',border:'1px solid '+(i===0?'var(--cnc-charcoal)':'var(--border-subtle)'),borderRadius:'var(--radius-pill)',padding:'7px 14px',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12,cursor:'pointer'}}>{t}</span>)}
    </div>
    <SectionLabel>Audiometer daily checklist · version 3 · active</SectionLabel>
    <div style={{marginTop:10}}>
    <TableCard>
      <thead><tr><Th>Code</Th><Th>Item</Th><Th>Critical</Th><Th right>Edit</Th></tr></thead>
      <tbody>
        {items.map((c,i)=><tr key={c.code}>
          <Td>{c.code}</Td>
          <Td strong><input defaultValue={c.label} style={{border:'1px solid transparent',borderRadius:4,padding:'4px 6px',fontSize:13.5,width:'100%',fontFamily:'var(--font-body)',background:'transparent'}} onFocus={e=>e.target.style.border='1px solid var(--cnc-red)'} onBlur={e=>e.target.style.border='1px solid transparent'}/></Td>
          <Td><Switch checked={c.critical} onChange={()=>setItems(items.map((x,j)=>j===i?{...x,critical:!x.critical}:x))}/></Td>
          <Td right><Button size="sm" variant="ghost">Remove</Button></Td>
        </tr>)}
      </tbody>
    </TableCard>
    </div>
    <div style={{marginTop:10}}><Button variant="secondary" size="sm" icon={<I n="plus" size={14}/>}>Add checklist item</Button></div>
  </div>;
}

function BackendDevices(){
  return <div style={{maxWidth:980}}>
    <PageTitle title="Device registry" sub="Lifetime volumes and projected service dates, learnt from real usage"/>
    <TableCard>
      <thead><tr><Th>Device</Th><Th>Unit</Th><Th right>Lifetime tests</Th><Th right>Since calibration</Th><Th right>Avg per day</Th><Th right>Service in</Th><Th>Status</Th></tr></thead>
      <tbody>
        {window.CNC.devices.map(d=><tr key={d.id}>
          <Td strong>{d.device_type}<div style={{fontSize:11.5,color:'var(--text-muted)',fontWeight:400}}>{d.barcode} · {d.make}</div></Td>
          <Td>{d.unit}</Td>
          <Td right>{d.lifetime.toLocaleString('en-ZA')}</Td>
          <Td right>{d.since_cal}</Td>
          <Td right>{d.avg_daily}</Td>
          <Td right strong>{d.service_in} days</Td>
          <Td>{d.status==='do_not_use'?<Badge tone="red">Do not use</Badge>:<Badge tone="green">In service</Badge>}</Td>
        </tr>)}
      </tbody>
    </TableCard>
    <div style={{marginTop:14}}>
      <Banner tone="blue" icon="flask" title="Lifecycle learning">Out of tolerance events are correlated against test counts in the weekly digest, so each device class earns a real service threshold over time.</Banner>
    </div>
  </div>;
}

function BackendReports(){
  const r=window.CNC.agentReport;
  return <div style={{maxWidth:820}}>
    <PageTitle title="Agent reports" sub="Written daily at 05:00 SAST by the audit agent. It reads operational tables only, recommends, and never decides." right={<Button size="sm" variant="secondary" icon={<I n="mail" size={14}/>}>Email settings</Button>}/>
    <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',boxShadow:'var(--shadow-card)',padding:'30px 34px'}}>
      <div style={{display:'flex',alignItems:'center',gap:12}}>
        <img src="assets/logo-horizontal.png" alt="" style={{height:24}}/>
        <div style={{marginLeft:'auto',fontSize:12,color:'var(--text-muted)'}}>Daily exception report · {r.date}</div>
      </div>
      <Pulse height={22} style={{margin:'16px 0 4px'}}/>
      <div style={{fontFamily:'var(--font-display)',fontSize:28,letterSpacing:'.02em',margin:'10px 0 2px'}}>Daily exception report</div>
      <div style={{fontSize:12.5,color:'var(--text-muted)'}}>Generated {r.generated} · covers operations of 05/08/2026 · {r.items.length} findings</div>
      <div style={{display:'flex',flexDirection:'column',gap:14,marginTop:20}}>
        {r.items.map((it,i)=><div key={i} style={{display:'flex',gap:14}}>
          <div style={{flex:'none',width:64}}><Badge tone={sevTone[it.sev]}>{it.sev}</Badge></div>
          <div style={{flex:1,borderBottom:i<r.items.length-1?'1px solid var(--surface-panel)':'none',paddingBottom:14}}>
            <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14}}>{i+1}. {it.title}</div>
            <div style={{fontSize:13.5,color:'var(--cnc-charcoal)',lineHeight:1.6,marginTop:4}}>{it.body}</div>
          </div>
        </div>)}
      </div>
      <div style={{fontSize:12,color:'var(--text-muted)',marginTop:18,lineHeight:1.55}}>This report was produced by the daily audit agent from operational records only. It has no access to Speak Out submissions or authentication data, and holds no write access to source records. Decisions rest with people.</div>
    </div>
  </div>;
}
Object.assign(window,{Backend});
