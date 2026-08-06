// Minimal Lucide-style stroke icons (1.75px stroke, currentColor)
function Ic({d,size=20,style,children}){
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" strokeLinejoin="round" style={style}>{children||<path d={d}/>}</svg>;
}
const ICONS = {
home:<React.Fragment><path d="M3 10.5 12 3l9 7.5"/><path d="M5 9.5V21h14V9.5"/></React.Fragment>,
inspect:<React.Fragment><path d="M9 3H5a2 2 0 0 0-2 2v4"/><path d="M15 3h4a2 2 0 0 1 2 2v4"/><path d="M9 21H5a2 2 0 0 1-2-2v-4"/><path d="M15 21h4a2 2 0 0 0 2-2v-4"/><path d="M7 12h10"/></React.Fragment>,
clock:<React.Fragment><circle cx="12" cy="12" r="9"/><path d="M12 7v5l3 2"/></React.Fragment>,
stock:<React.Fragment><path d="M21 8 12 3 3 8v8l9 5 9-5Z"/><path d="M3 8l9 5 9-5"/><path d="M12 13v8"/></React.Fragment>,
more:<React.Fragment><circle cx="5" cy="12" r="1.4"/><circle cx="12" cy="12" r="1.4"/><circle cx="19" cy="12" r="1.4"/></React.Fragment>,
camera:<React.Fragment><path d="M4 8h3l2-3h6l2 3h3a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1Z"/><circle cx="12" cy="13.5" r="3.5"/></React.Fragment>,
check:<path d="M4 12.5 10 18 20 6"/>,
x:<React.Fragment><path d="M6 6l12 12"/><path d="M18 6 6 18"/></React.Fragment>,
alert:<React.Fragment><path d="M12 3 2.5 20h19L12 3Z"/><path d="M12 10v4"/><path d="M12 17.2v.1"/></React.Fragment>,
chevR:<path d="m9 5 7 7-7 7"/>,
back:<path d="m15 5-7 7 7 7"/>,
truck:<React.Fragment><path d="M2 6h12v11H2z"/><path d="M14 10h4l3 3v4h-7"/><circle cx="6" cy="17.5" r="1.8"/><circle cx="17.5" cy="17.5" r="1.8"/></React.Fragment>,
flask:<React.Fragment><path d="M10 3v6L4.5 19a1.5 1.5 0 0 0 1.3 2.2h12.4A1.5 1.5 0 0 0 19.5 19L14 9V3"/><path d="M8.5 3h7"/></React.Fragment>,
building:<React.Fragment><path d="M4 21V5a1 1 0 0 1 1-1h9a1 1 0 0 1 1 1v16"/><path d="M15 9h4a1 1 0 0 1 1 1v11"/><path d="M4 21h17"/><path d="M8 8h3M8 12h3M8 16h3"/></React.Fragment>,
shield:<React.Fragment><path d="M12 3c3 1.5 6 2 8 2v7c0 4.5-3.5 7.5-8 9-4.5-1.5-8-4.5-8-9V5c2 0 5-.5 8-2Z"/></React.Fragment>,
file:<React.Fragment><path d="M14 3H6a1 1 0 0 0-1 1v16a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1V8l-5-5Z"/><path d="M14 3v5h5"/></React.Fragment>,
mail:<React.Fragment><rect x="3" y="5" width="18" height="14" rx="1.5"/><path d="m3 7 9 6 9-6"/></React.Fragment>,
torch:<React.Fragment><path d="M9 3h6v4l-1.5 2v12h-3V9L9 7V3Z"/></React.Fragment>,
gps:<React.Fragment><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M2 12h3M19 12h3"/></React.Fragment>,
offline:<React.Fragment><path d="M5 12.5a10 10 0 0 1 14 0"/><path d="M8.5 16a5 5 0 0 1 7 0"/><circle cx="12" cy="19" r="1"/><path d="M3 3l18 18"/></React.Fragment>,
user:<React.Fragment><circle cx="12" cy="8" r="4"/><path d="M4 21c1.5-3.5 4.5-5 8-5s6.5 1.5 8 5"/></React.Fragment>,
speak:<React.Fragment><path d="M21 12a8 8 0 0 1-8 8H4l2-3a8 8 0 1 1 15-5Z"/></React.Fragment>,
news:<React.Fragment><rect x="3" y="4" width="15" height="17" rx="1.5"/><path d="M18 8h2a1 1 0 0 1 1 1v10a2 2 0 0 1-2 2"/><path d="M7 8h7M7 12h7M7 16h4"/></React.Fragment>,
plus:<path d="M12 5v14M5 12h14"/>,
minus:<path d="M5 12h14"/>,
search:<React.Fragment><circle cx="11" cy="11" r="6.5"/><path d="m16 16 5 5"/></React.Fragment>,
settings:<React.Fragment><circle cx="12" cy="12" r="3"/><path d="M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.4-2.3 1a7 7 0 0 0-2-1.2L14.2 3h-4l-.4 2.5a7 7 0 0 0-2 1.2l-2.3-1-2 3.4 2 1.5a7 7 0 0 0 0 2.4l-2 1.5 2 3.4 2.3-1a7 7 0 0 0 2 1.2l.4 2.5h4l.4-2.5a7 7 0 0 0 2-1.2l2.3 1 2-3.4-2-1.5c.06-.4.1-.8.1-1.2Z"/></React.Fragment>,
logout:<React.Fragment><path d="M9 21H5a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/></React.Fragment>,
};
function I({n,size=20,style}){return <Ic size={size} style={style}>{ICONS[n]}</Ic>;}
Object.assign(window,{I});
