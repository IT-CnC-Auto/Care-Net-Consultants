// Module 01: Authentication and User Management
function LoginScreen({onLogin,onRegister}){
  const [step,setStep]=React.useState('login');
  const [code,setCode]=React.useState('');
  const [reset,setReset]=React.useState(false);
  if(step==='forgot') return <Screen pad bar={<AppBar onBack={()=>{setStep('login');setReset(false);}} title="Forgot my password"/>}>
    {!reset?<React.Fragment>
      <div style={{padding:'18px 4px 0'}}>
        <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:22}}>We will text you a code</div>
        <div style={{fontSize:13.5,color:'var(--text-muted)',marginTop:6,lineHeight:1.5}}>A reset code will be sent by SMS to your registered cell number.</div>
      </div>
      <div style={{background:'#fff',border:'1px solid var(--border-subtle)',borderRadius:'var(--radius-md)',padding:'14px 16px',display:'flex',alignItems:'center',gap:12}}>
        <span style={{width:36,height:36,borderRadius:'50%',background:'var(--red-tint)',color:'var(--cnc-red)',display:'flex',alignItems:'center',justifyContent:'center',flex:'none'}}><I n="mail" size={17}/></span>
        <div>
          <div style={{fontFamily:'var(--font-heading)',fontWeight:700,fontSize:14,fontVariantNumeric:'tabular-nums'}}>082 *** 0142</div>
          <div style={{fontSize:12,color:'var(--text-muted)',marginTop:2}}>Registered number on your employee profile</div>
        </div>
      </div>
      <Button size="lg" style={{width:'100%',justifyContent:'center'}} onClick={()=>setReset(true)}>Send me the SMS code</Button>
      <div style={{fontSize:12,color:'var(--text-muted)',textAlign:'center',lineHeight:1.5}}>Number changed? Contact HR to update your registered number first.</div>
    </React.Fragment>
    :<React.Fragment>
      <div style={{display:'flex',flexDirection:'column',alignItems:'center',textAlign:'center',gap:12,padding:'30px 12px'}}>
        <div style={{width:56,height:56,borderRadius:'50%',background:'var(--green-tint)',color:'var(--cnc-green)',display:'flex',alignItems:'center',justifyContent:'center'}}><I n="check" size={24}/></div>
        <div style={{fontFamily:'var(--font-display)',fontSize:26,letterSpacing:'.02em'}}>Code sent to 082 *** 0142</div>
        <div style={{fontSize:13.5,color:'var(--text-muted)',maxWidth:270,lineHeight:1.5}}>Enter it on the next screen, then choose a new password.</div>
      </div>
      <Input label="SMS code" placeholder="6 digit code"/>
      <Input label="New password" type="password" placeholder="••••••••"/>
      <Input label="Confirm new password" type="password" placeholder="••••••••"/>
      <Button size="lg" style={{width:'100%',justifyContent:'center'}} onClick={()=>{setStep('login');setReset(false);}}>Reset my password</Button>
    </React.Fragment>}
  </Screen>;
  if(step==='2fa') return <Screen pad bar={<AppBar onBack={()=>setStep('login')} title="Two step verification"/>}>
    <div style={{padding:'18px 4px 0'}}>
      <div style={{fontFamily:'var(--font-heading)',fontWeight:800,fontSize:22}}>Enter your code</div>
      <div style={{fontSize:13.5,color:'var(--text-muted)',marginTop:6,lineHeight:1.5}}>Open your authenticator app and enter the six digit code for Care Net Consultants.</div>
    </div>
    <div style={{display:'flex',gap:8,justifyContent:'center',padding:'8px 0'}}>
      {[0,1,2,3,4,5].map(i=><div key={i} style={{width:44,height:52,border:code.length===i?'1.5px solid var(--cnc-red)':'1px solid var(--border-subtle)',borderRadius:'var(--radius-sm)',background:'#fff',display:'flex',alignItems:'center',justifyContent:'center',fontFamily:'var(--font-heading)',fontWeight:700,fontSize:20,fontVariantNumeric:'tabular-nums'}}>{code[i]||''}</div>)}
    </div>
    <div style={{display:'grid',gridTemplateColumns:'repeat(3,1fr)',gap:8,padding:'0 12px'}}>
      {['1','2','3','4','5','6','7','8','9','','0','⌫'].map((k,i)=><button key={i} disabled={k===''} onClick={()=>{ if(k==='⌫'){setCode(code.slice(0,-1));} else { const c=code+k; setCode(c); if(c.length===6) setTimeout(onLogin,350);} }} style={{height:52,border:'none',background:k===''?'transparent':'#fff',borderRadius:'var(--radius-sm)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:19,cursor:'pointer',boxShadow:k===''?'none':'var(--shadow-card)'}}>{k}</button>)}
    </div>
    <button style={{border:'none',background:'none',color:'var(--cnc-red)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13,cursor:'pointer',padding:10}}>Send a code by SMS instead</button>
  </Screen>;
  if(step==='pending') return <Screen pad bar={<AppBar onBack={()=>setStep('login')} title="Registration"/>}>
    <div style={{display:'flex',flexDirection:'column',alignItems:'center',textAlign:'center',gap:12,padding:'40px 12px'}}>
      <div style={{width:60,height:60,borderRadius:'50%',background:'var(--yellow-tint)',display:'flex',alignItems:'center',justifyContent:'center',color:'#8a6100'}}><I n="clock" size={26}/></div>
      <div style={{fontFamily:'var(--font-display)',fontSize:30,letterSpacing:'.02em'}}>Thank you, Zanele</div>
      <div style={{fontSize:14,color:'var(--text-muted)',maxWidth:270,lineHeight:1.55}}>Your registration is with an administrator for approval. You will receive an email once your profile is active.</div>
      <Pulse variant="standard" height={40} style={{alignSelf:'center'}}/>
    </div>
  </Screen>;
  if(step==='register') return <RegisterScreen onBack={()=>setStep('login')} onDone={()=>setStep('pending')}/>;
  return <div style={{display:'flex',flexDirection:'column',height:'100%',background:'#fff'}}>
    <div style={{background:'var(--cnc-black)',padding:'34px 24px 24px',color:'#fff'}}>
      <img src="assets/logo-stacked.png" alt="Care Net Consultants" style={{width:92,background:'#fff',borderRadius:10,padding:'8px 10px'}}/>
      <div style={{fontFamily:'var(--font-display)',fontSize:32,letterSpacing:'.02em',lineHeight:1.05,marginTop:16}}>Employee Operations</div>
      <div style={{fontSize:13.5,opacity:.92,marginTop:4,fontStyle:'italic'}}>I am because we are.</div>
      <Pulse white height={34} style={{marginTop:12}}/>
    </div>
    <div style={{padding:24,display:'flex',flexDirection:'column',gap:14,flex:1,overflow:'auto'}}>
      <Input label="Work email" placeholder="name@carenetconsultants.co.za"/>
      <Input label="Password" type="password" placeholder="••••••••"/>
      <Button size="lg" style={{width:'100%',justifyContent:'center'}} onClick={()=>setStep('2fa')}>Sign in</Button>
      <div style={{display:'flex',alignItems:'center',gap:12,color:'var(--text-muted)',fontSize:12}}>
        <div style={{flex:1,height:1,background:'var(--border-subtle)'}}></div>or continue with<div style={{flex:1,height:1,background:'var(--border-subtle)'}}></div>
      </div>
      <div style={{display:'flex',gap:10}}>
        <Button variant="secondary" style={{flex:1,justifyContent:'center'}} onClick={()=>setStep('2fa')} icon={<svg width="15" height="15" viewBox="0 0 21 21"><rect x="1" y="1" width="9" height="9" fill="#F25022"/><rect x="11" y="1" width="9" height="9" fill="#7FBA00"/><rect x="1" y="11" width="9" height="9" fill="#00A4EF"/><rect x="11" y="11" width="9" height="9" fill="#FFB900"/></svg>}>Microsoft</Button>
        <Button variant="secondary" style={{flex:1,justifyContent:'center'}} onClick={()=>setStep('2fa')} icon={<svg width="15" height="15" viewBox="0 0 24 24"><path fill="#4285F4" d="M23.5 12.3c0-.9-.1-1.5-.3-2.2H12v4.1h6.5c-.1 1.1-.8 2.7-2.4 3.8l3.7 2.9c2.2-2 3.7-5 3.7-8.6z"/><path fill="#34A853" d="M12 24c3.2 0 5.9-1.1 7.9-2.9l-3.7-2.9c-1 .7-2.4 1.2-4.2 1.2-3.2 0-5.9-2.1-6.9-5l-3.9 3C3.2 21.3 7.3 24 12 24z"/><path fill="#FBBC05" d="M5.1 14.4c-.2-.7-.4-1.5-.4-2.4s.1-1.7.4-2.4l-3.9-3C.4 8.2 0 10 0 12s.4 3.8 1.2 5.4l3.9-3z"/><path fill="#EA4335" d="M12 4.7c1.8 0 3 .8 3.7 1.4l3.3-3.2C17.9 1.1 15.2 0 12 0 7.3 0 3.2 2.7 1.2 6.6l3.9 3c1-2.9 3.7-4.9 6.9-4.9z"/></svg>}>Google</Button>
      </div>
      <Button variant="dark" style={{width:'100%',justifyContent:'center'}} onClick={()=>setStep('2fa')} icon={<I n="shield" size={16}/>}>Company SSO single sign on</Button>
      <button onClick={()=>setStep('forgot')} style={{border:'none',background:'none',color:'var(--cnc-charcoal)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13,cursor:'pointer',padding:8}}>Forgot my password? Send an SMS to my registered number</button>
      <button onClick={()=>setStep('register')} style={{border:'none',background:'none',color:'var(--cnc-red)',fontFamily:'var(--font-heading)',fontWeight:600,fontSize:13.5,cursor:'pointer',padding:8,marginTop:'auto'}}>New employee? Register your profile</button>
    </div>
    <div style={{height:10,background:'url(assets/pattern-band-4k.png) repeat-x',backgroundSize:'auto 100%',flex:'none'}}></div>
  </div>;
}

function RegisterScreen({onBack,onDone}){
  const [photo,setPhoto]=React.useState(false);
  const [cam,setCam]=React.useState(false);
  const [c1,setC1]=React.useState(false);
  const [c2,setC2]=React.useState(false);
  return <Screen pad bar={<AppBar onBack={onBack} title="Register your profile"/>}
    sticky={<StickyBar><Button size="lg" style={{flex:1,justifyContent:'center'}} disabled={!(photo&&c1&&c2)} onClick={onDone}>Submit for approval</Button></StickyBar>}>
    {cam&&<CamView frameLabel="Reference photograph" torchable={false} onCancel={()=>setCam(false)} onCapture={()=>{setPhoto(true);setCam(false);}}/>}
    <SectionLabel>Your details</SectionLabel>
    <div style={{display:'grid',gridTemplateColumns:'1fr 1fr',gap:10}}>
      <Input label="First name" placeholder="Zanele"/>
      <Input label="Surname" placeholder="Mthembu"/>
    </div>
    <Input label="Employee number" placeholder="CNC0183"/>
    <Input label="Work email" placeholder="name@carenetconsultants.co.za"/>
    <Input label="Cell number" placeholder="082 000 0000"/>
    <SectionLabel>Reference photograph</SectionLabel>
    <div style={{display:'grid',gridTemplateColumns:'1fr',gap:8}}>
      <PhotoTile wide label={photo?'Reference photograph captured':'Take your reference photograph'} taken={photo} onTake={()=>setCam(true)}/>
    </div>
    <div style={{fontSize:12.5,color:'var(--text-muted)',lineHeight:1.5}}>This photograph is used only to verify that it is you clocking in on a shared device. It is stored securely and never shared.</div>
    <SectionLabel>Consent</SectionLabel>
    <Card>
      <div style={{display:'flex',flexDirection:'column',gap:14}}>
        <Checkbox label="I consent to Care Net Consultants processing my personal information for employment purposes under POPIA." checked={c1} onChange={()=>setC1(!c1)}/>
        <div style={{height:1,background:'var(--border-subtle)'}}></div>
        <Checkbox label="I separately consent to my reference photograph being used to verify my identity when I clock in. I may withdraw this consent at any time." checked={c2} onChange={()=>setC2(!c2)}/>
      </div>
    </Card>
    <div style={{height:4}}></div>
  </Screen>;
}
Object.assign(window,{LoginScreen,RegisterScreen});
