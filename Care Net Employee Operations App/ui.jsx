const DS = window.CareNetConsultantsDesignSystem_7580a9;
const {Button,Input,Select,Checkbox,Radio,Switch,Card,Badge,Tabs,StatusChip,Dialog,Toast} = DS;

function FramedAvatar({name='Thandi Mokoena',size=48,inner,photo=true,pulse}){
  const inSize=inner||Math.round(size*.72);
  return <span style={{position:'relative',width:size,height:size,display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}>
    {pulse&&<span style={{position:'absolute',inset:size*.06,borderRadius:'50%',border:'2.5px solid var(--cnc-red)',animation:'cncring 1.6s ease-out infinite'}}></span>}
    {pulse&&<span style={{position:'absolute',inset:size*.06,borderRadius:'50%',border:'2px solid var(--cnc-red)',animation:'cncring 1.6s ease-out .5s infinite'}}></span>}
    <img src="assets/avatar-ring.png" alt="" style={{position:'absolute',inset:0,width:'100%',height:'100%',filter:pulse?'drop-shadow(0 0 6px rgba(237,27,36,.45))':'none'}}/>
    <span style={{width:inSize,height:inSize,borderRadius:'50%',background:'#E9E4DD',display:'flex',alignItems:'flex-end',justifyContent:'center',overflow:'hidden'}}>
      {photo?<svg viewBox="0 0 48 48" width={inSize} height={inSize} aria-label={name}>
        <circle cx="24" cy="24" r="24" fill="#E9E4DD"/>
        <circle cx="24" cy="18.5" r="8.2" fill="#8C6748"/>
        <path d="M24 10.5c-5 0-8.6 3.4-8.4 8 .1-3 3.9-4.6 8.4-4.6s8.3 1.6 8.4 4.6c.2-4.6-3.4-8-8.4-8Z" fill="#2B2320"/>
        <path d="M8 48c1.4-9.2 8-13.4 16-13.4S38.6 38.8 40 48Z" fill="var(--cnc-red)"/>
        <path d="M18 35.6c1.8-.9 3.8-1 6-1s4.2.1 6 1L24 42Z" fill="#fff"/>
      </svg>
      :<span style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:inSize*.36,color:'var(--cnc-red)',alignSelf:'center'}}>{name.split(' ').map(x=>x[0]).join('').slice(0,2)}</span>}
    </span>
  </span>;
}

function AvatarMenu({dark,onProfile,onHR,size=46,pulse}){
  const [open,setOpen]=React.useState(false);
  return <div style={{position:'relative'}}>
    <button onClick={()=>setOpen(!open)} aria-label="My account" style={{border:'none',background:'none',cursor:'pointer',padding:0,display:'flex',flexDirection:'column',alignItems:'center',gap:2}}>
      <FramedAvatar size={size} pulse={pulse}/>
      <span style={{width:5,height:5,borderRadius:'50%',background:'var(--cnc-red)'}}></span>
    </button>
    {open&&<div style={{position:'absolute',top:size+8,right:0,zIndex:60,background:'#fff',borderRadius:'var(--radius-md)',boxShadow:'var(--shadow-raised)',border:'1px solid var(--border-subtle)',width:230,overflow:'hidden'}}>
      <div style={{padding:'12px 14px',borderBottom:'1px solid var(--border-subtle)'}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13.5,color:'var(--cnc-charcoal)'}}>Thandi Mokoena</div>
        <div style={{fontSize:11.5,color:'var(--text-muted)',marginTop:1}}>CNC0142 · OHS practitioner</div>
      </div>
      <div style={{padding:'10px 12px'}}><button onClick={()=>{setOpen(false);onProfile&&onProfile();}} style={{display:'flex',alignItems:'center',justifyContent:'center',gap:8,width:'100%',border:'none',background:'var(--cnc-red)',color:'#fff',borderRadius:'var(--radius-sm)',padding:'12px 14px',cursor:'pointer',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13.5,minHeight:48}}><I n="user" size={17}/>Edit my details</button></div>
      <button onClick={()=>{setOpen(false);onHR&&onHR();}} style={{display:'flex',alignItems:'center',gap:10,width:'100%',textAlign:'left',border:'none',background:'none',padding:'12px 14px',cursor:'pointer',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13,color:'var(--cnc-charcoal)',minHeight:44,borderTop:'1px solid var(--surface-panel)'}}><I n="shield" size={17}/>HR dashboard · leave</button>
    </div>}
  </div>;
}

function AppBar({title,onBack,right}){
  return <div style={{background:'#fff',borderBottom:'1px solid var(--border-subtle)',padding:'12px 16px',display:'flex',alignItems:'center',gap:12,flex:'none'}}>
    {onBack?<button onClick={onBack} aria-label="Back" style={{border:'none',background:'none',cursor:'pointer',color:'var(--cnc-charcoal)',padding:4,margin:-4,display:'flex'}}><I n="back" size={22}/></button>:<img src="assets/logo-horizontal.png" alt="Care Net Consultants" style={{height:24}}/>}
    <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:15,color:'var(--cnc-charcoal)',flex:1,minWidth:0,whiteSpace:'nowrap',overflow:'hidden',textOverflow:'ellipsis'}}>{onBack?title:''}</div>
    {!onBack&&<div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:12,color:'var(--text-muted)'}}>{title}</div>}
    {right}
    {!onBack&&window.__omGo&&<AvatarMenu onProfile={()=>window.__omGo('profile')} onHR={()=>window.__omGo('hr')}/>}
  </div>;
}

function BottomNav({active,onNav}){
  const items=[['home','Home'],['jobcard','Jobcard'],['inspect','Inspect'],['stock','Stock'],['more','More']];
  return <div style={{display:'flex',background:'#fff',borderTop:'1px solid var(--border-subtle)',flex:'none'}}>
    {items.map(([k,l])=><button key={k} onClick={()=>onNav(k)} style={{flex:1,border:'none',background:'none',cursor:'pointer',padding:'8px 0 10px',display:'flex',flexDirection:'column',alignItems:'center',gap:3,color:active===k?'var(--cnc-red)':'var(--text-muted)',minHeight:48}}>
      <I n={k==='jobcard'?'file':k} size={21}/>
      <span style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:10.5}}>{l}</span>
    </button>)}
  </div>;
}

function Screen({bar,children,nav,sticky,pad=true}){
  return <div style={{display:'flex',flexDirection:'column',height:'100%',background:'var(--surface-panel)'}}>
    {bar}
    <div className="cnc-scroll" style={{flex:1,overflow:'auto',overflowX:'hidden',padding:pad?16:0,display:'flex',flexDirection:'column',gap:12}}>{children}</div>
    {sticky}
    {nav}
  </div>;
}

function StickyBar({children}){
  return <div style={{padding:'12px 16px',background:'#fff',borderTop:'1px solid var(--border-subtle)',display:'flex',gap:10,flex:'none'}}>{children}</div>;
}

function Pulse({variant='heart',height=36,white,style,still}){
  const src={standard:'assets/pulse-standard.png',heart:'assets/pulse-heart-red.png',protea:'assets/pulse-protea-red.png'}[variant]||'assets/pulse-heart-red.png';
  const img=i=><img key={i} src={src} alt="" style={{height,flex:'none',filter:white?'brightness(0) invert(1)':'none'}}/>;
  if(still||height<16) return <img src={src} alt="" style={{height,alignSelf:'flex-start',filter:white?'brightness(0) invert(1)':'none',...style}}/>;
  const line={flex:1,height:1.5,background:white?'#fff':'var(--cnc-red)',opacity:.9};
  return <div style={{width:'100%',display:'flex',alignItems:'center',height,gap:0,...style}}>
    <span style={line}></span>
    <img src={src} alt="" style={{height,flex:'none',filter:white?'brightness(0) invert(1)':'none',animation:'cncbeat 1.4s ease-in-out infinite',transformOrigin:'center'}}/>
    <span style={line}></span>
  </div>;
}

function SectionLabel({children}){
  return <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:11.5,letterSpacing:'.08em',textTransform:'uppercase',color:'var(--text-muted)'}}>{children}</div>;
}

// Pass / Fail / N/A segmented row
function SegPFN({value,onChange}){
  const opts=[['pass','Pass','var(--cnc-green)','var(--green-tint)'],['fail','Fail','var(--cnc-red)','var(--red-tint)'],['na','N/A','var(--text-muted)','var(--surface-panel)']];
  return <div style={{display:'flex',gap:6}}>
    {opts.map(([k,l,c,bg])=><button key={k} onClick={()=>onChange(k)} style={{flex:1,minHeight:44,border:value===k?'1.5px solid '+c:'1px solid var(--border-subtle)',background:value===k?bg:'#fff',color:value===k?c:'var(--text-muted)',borderRadius:'var(--radius-sm)',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,cursor:'pointer'}}>{l}</button>)}
  </div>;
}

// Simulated captured-photo tile
function PhotoTile({label,taken,onTake,wide}){
  return <button onClick={onTake} style={{border:taken?'1.5px solid var(--cnc-green)':'1.5px dashed var(--border-subtle)',background:taken?'var(--cnc-charcoal)':'#fff',borderRadius:'var(--radius-sm)',minHeight:wide?92:78,cursor:'pointer',display:'flex',flexDirection:'column',alignItems:'center',justifyContent:'center',gap:6,color:taken?'#fff':'var(--text-muted)',padding:8,position:'relative',overflow:'hidden'}}>
    {taken&&<div style={{position:'absolute',inset:0,background:'repeating-linear-gradient(135deg,#2A2A2A 0 10px,#242424 10px 20px)'}}></div>}
    <div style={{position:'relative',display:'flex',flexDirection:'column',alignItems:'center',gap:5}}>
      <I n={taken?'check':'camera'} size={20}/>
      <span style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:11}}>{label}</span>
    </div>
    {taken&&<span style={{position:'absolute',top:6,right:6,width:18,height:18,borderRadius:'50%',background:'var(--cnc-green)',color:'#fff',display:'flex',alignItems:'center',justifyContent:'center'}}><I n="check" size={11}/></span>}
  </button>;
}

// Simulated camera viewfinder (full-bleed dark)
function CamView({frameLabel,onCapture,onCancel,scan,torchable=true,children}){
  const [torch,setTorch]=React.useState(false);
  return <div style={{position:'absolute',inset:0,background:'#101010',display:'flex',flexDirection:'column',zIndex:5}}>
    <div style={{display:'flex',alignItems:'center',padding:'14px 16px',color:'#fff',gap:12}}>
      <button onClick={onCancel} aria-label="Cancel" style={{border:'none',background:'rgba(255,255,255,.12)',color:'#fff',borderRadius:'50%',width:38,height:38,display:'flex',alignItems:'center',justifyContent:'center',cursor:'pointer'}}><I n="x" size={18}/></button>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:600,fontSize:14,flex:1}}>{frameLabel}</div>
      {torchable&&<button onClick={()=>setTorch(!torch)} aria-label="Torch" style={{border:'none',background:torch?'#fff':'rgba(255,255,255,.12)',color:torch?'var(--cnc-charcoal)':'#fff',borderRadius:'50%',width:38,height:38,display:'flex',alignItems:'center',justifyContent:'center',cursor:'pointer'}}><I n="torch" size={18}/></button>}
    </div>
    <div style={{flex:1,position:'relative',display:'flex',alignItems:'center',justifyContent:'center'}}>
      <div style={{position:'absolute',inset:0,background:'radial-gradient(circle at 50% 42%, #3A3A3A 0%, #191919 70%)',opacity:torch?1:.75}}></div>
      {scan?
        <div style={{position:'relative',width:'78%',aspectRatio:'1.6',border:'2.5px solid var(--cnc-red)',borderRadius:12,boxShadow:'0 0 0 2000px rgba(0,0,0,.45)'}}>
          <div className="cnc-scanline" style={{position:'absolute',left:8,right:8,height:2,background:'var(--cnc-red)',top:'20%'}}></div>
        </div>
        :
        <div style={{position:'relative',width:'62%',aspectRatio:'.82',border:'2.5px solid #fff',borderRadius:'50% 50% 46% 46%',boxShadow:'0 0 0 2000px rgba(0,0,0,.45)'}}></div>}
      {children}
    </div>
    <div style={{padding:'18px 0 26px',display:'flex',justifyContent:'center'}}>
      <button onClick={onCapture} aria-label="Capture" style={{width:66,height:66,borderRadius:'50%',border:'4px solid #fff',background:'var(--cnc-red)',cursor:'pointer'}}></button>
    </div>
  </div>;
}

function Avatar({name,size=40,tone}){
  const ini=name.split(' ').map(x=>x[0]).join('').slice(0,2);
  return <div style={{width:size,height:size,borderRadius:'50%',background:tone==='red'?'var(--red-tint)':'var(--surface-panel)',color:tone==='red'?'var(--cnc-red)':'var(--text-muted)',display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:size*.34,flex:'none'}}>{ini}</div>;
}

function ListRow({icon,title,sub,right,onClick,danger}){
  return <button onClick={onClick} style={{display:'flex',alignItems:'center',gap:12,width:'100%',textAlign:'left',background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'13px 14px',cursor:onClick?'pointer':'default',minHeight:52}}>
    {icon&&<span style={{color:danger?'var(--cnc-red)':'var(--cnc-charcoal)',display:'flex',flex:'none'}}><I n={icon} size={21}/></span>}
    <span style={{flex:1,minWidth:0}}>
      <span style={{display:'block',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:14,color:'var(--cnc-charcoal)'}}>{title}</span>
      {sub&&<span style={{display:'block',fontSize:12.5,color:'var(--text-muted)',marginTop:2}}>{sub}</span>}
    </span>
    {right||<span style={{color:'var(--text-muted)',display:'flex'}}><I n="chevR" size={18}/></span>}
  </button>;
}

function Banner({tone='red',icon='alert',title,children}){
  const c={red:['var(--cnc-red)','var(--red-tint)'],green:['var(--cnc-green)','var(--green-tint)'],yellow:['#8a6100','var(--yellow-tint)'],blue:['var(--cnc-blue)','var(--blue-tint)']}[tone];
  return <div style={{background:c[1],border:'1px solid '+c[0]+'33',borderRadius:'var(--radius-md)',padding:'12px 14px',display:'flex',gap:10,alignItems:'flex-start'}}>
    <span style={{color:c[0],display:'flex',flex:'none',marginTop:1}}><I n={icon} size={18}/></span>
    <div style={{fontSize:13,color:'var(--cnc-charcoal)',lineHeight:1.5}}>
      {title&&<div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:13,color:c[0],marginBottom:2}}>{title}</div>}
      {children}
    </div>
  </div>;
}

function BigNum({v,label}){
  return <div style={{textAlign:'center'}}>
    <div style={{fontFamily:'var(--font-display)',fontSize:30,letterSpacing:'.02em',lineHeight:1,fontVariantNumeric:'tabular-nums'}}>{v}</div>
    <div style={{fontSize:11.5,color:'var(--text-muted)',marginTop:3}}>{label}</div>
  </div>;
}

Object.assign(window,{DS,Button,Input,Select,Checkbox,Radio,Switch,Card,Badge,Tabs,StatusChip,Dialog,Toast,AppBar,BottomNav,Screen,StickyBar,Pulse,SectionLabel,SegPFN,PhotoTile,CamView,Avatar,ListRow,Banner,BigNum,AvatarMenu,FramedAvatar});
