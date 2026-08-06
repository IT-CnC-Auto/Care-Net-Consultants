/* @ds-bundle: {"format":4,"namespace":"CareNetConsultantsDesignSystem_7580a9","components":[{"name":"Logo","sourcePath":"components/brand/Logo.jsx"},{"name":"PulseLine","sourcePath":"components/brand/PulseLine.jsx"},{"name":"Badge","sourcePath":"components/core/Badge.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Card","sourcePath":"components/core/Card.jsx"},{"name":"Checkbox","sourcePath":"components/core/Checkbox.jsx"},{"name":"IconButton","sourcePath":"components/core/IconButton.jsx"},{"name":"Input","sourcePath":"components/core/Input.jsx"},{"name":"Radio","sourcePath":"components/core/Radio.jsx"},{"name":"Select","sourcePath":"components/core/Select.jsx"},{"name":"StatusChip","sourcePath":"components/core/StatusChip.jsx"},{"name":"Switch","sourcePath":"components/core/Switch.jsx"},{"name":"Tabs","sourcePath":"components/core/Tabs.jsx"},{"name":"Tag","sourcePath":"components/core/Tag.jsx"},{"name":"Dialog","sourcePath":"components/feedback/Dialog.jsx"},{"name":"Toast","sourcePath":"components/feedback/Toast.jsx"}],"sourceHashes":{"components/brand/Logo.jsx":"51c18c8b53ce","components/brand/PulseLine.jsx":"56d620e3c806","components/core/Badge.jsx":"301d9d61f5c9","components/core/Button.jsx":"06f605c8af4d","components/core/Card.jsx":"3cc3103e0902","components/core/Checkbox.jsx":"c6eea21dd9fc","components/core/IconButton.jsx":"86192c634817","components/core/Input.jsx":"319eeb3b9bb5","components/core/Radio.jsx":"852ba6d75359","components/core/Select.jsx":"f66e588233d2","components/core/StatusChip.jsx":"0f9505889f2b","components/core/Switch.jsx":"05f1797d6425","components/core/Tabs.jsx":"6caf3b9df869","components/core/Tag.jsx":"3d36eb7bc390","components/feedback/Dialog.jsx":"ed17e7e684e3","components/feedback/Toast.jsx":"c633c9d43a55","ui_kits/checkin_app/screens.jsx":"86c927d39c73"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.CareNetConsultantsDesignSystem_7580a9 = window.CareNetConsultantsDesignSystem_7580a9 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/brand/Logo.jsx
try { (() => {
function Logo({
  variant = 'horizontal',
  width,
  style
}) {
  const src = variant === 'stacked' ? 'assets/logo-stacked.png' : 'assets/logo-horizontal.png';
  return /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: "Care Net Consultants",
    style: {
      width: width ?? (variant === 'stacked' ? 140 : 260),
      display: 'block',
      ...style
    }
  });
}
Object.assign(__ds_scope, { Logo });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/Logo.jsx", error: String((e && e.message) || e) }); }

// components/brand/PulseLine.jsx
try { (() => {
// Official CNC pulse icon assets (assets/pulse/). Never redrawn.
function PulseLine({
  variant = 'standard',
  color = 'red',
  height = 64,
  style
}) {
  const src = variant === 'standard' ? 'assets/pulse/pulse-standard.png' : 'assets/pulse/pulse-' + variant + '-' + (color === 'white' ? 'black' : color) + '.png';
  const inv = color === 'white' ? {
    filter: 'invert(1)'
  } : {};
  return /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: "",
    style: {
      height,
      display: 'block',
      ...inv,
      ...style
    }
  });
}
Object.assign(__ds_scope, { PulseLine });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/brand/PulseLine.jsx", error: String((e && e.message) || e) }); }

// components/core/Badge.jsx
try { (() => {
function Badge({
  tone = 'neutral',
  children,
  style
}) {
  const t = {
    neutral: {
      background: 'var(--surface-panel)',
      color: 'var(--cnc-charcoal)'
    },
    red: {
      background: 'var(--red-tint)',
      color: 'var(--red-dark)'
    },
    green: {
      background: 'var(--green-tint)',
      color: 'var(--cnc-green)'
    },
    blue: {
      background: 'var(--blue-tint)',
      color: 'var(--cnc-blue)'
    },
    yellow: {
      background: 'var(--yellow-tint)',
      color: '#7a5600'
    },
    solid: {
      background: 'var(--cnc-red)',
      color: '#fff'
    }
  }[tone];
  return /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 11.5,
      letterSpacing: '.04em',
      padding: '4px 10px',
      borderRadius: 999,
      display: 'inline-block',
      ...t,
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { Badge });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Badge.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function Button({
  variant = 'primary',
  size = 'md',
  disabled,
  icon,
  children,
  onClick,
  style
}) {
  const pad = size === 'sm' ? '7px 14px' : size === 'lg' ? '13px 26px' : '10px 20px';
  const fs = size === 'sm' ? 13 : size === 'lg' ? 16 : 14;
  const base = {
    fontFamily: 'var(--font-heading)',
    fontWeight: 600,
    fontSize: fs,
    padding: pad,
    borderRadius: 'var(--radius-sm)',
    border: '1px solid transparent',
    cursor: disabled ? 'not-allowed' : 'pointer',
    display: 'inline-flex',
    alignItems: 'center',
    gap: 8,
    lineHeight: 1.2,
    transition: 'background var(--dur-fast) var(--ease-standard),color var(--dur-fast) var(--ease-standard)',
    opacity: disabled ? 0.45 : 1
  };
  const v = {
    primary: {
      background: 'var(--cnc-red)',
      color: '#fff'
    },
    secondary: {
      background: '#fff',
      color: 'var(--cnc-charcoal)',
      border: '1px solid var(--cnc-charcoal)'
    },
    ghost: {
      background: 'transparent',
      color: 'var(--cnc-red)'
    },
    dark: {
      background: 'var(--cnc-charcoal)',
      color: '#fff'
    }
  }[variant];
  const [h, setH] = React.useState(false);
  const hov = !disabled && h ? variant === 'primary' ? {
    background: 'var(--red-dark)'
  } : variant === 'ghost' ? {
    background: 'var(--red-tint)'
  } : variant === 'dark' ? {
    background: '#000'
  } : {
    background: 'var(--surface-panel)'
  } : {};
  return /*#__PURE__*/React.createElement("button", {
    style: {
      ...base,
      ...v,
      ...hov,
      ...style
    },
    disabled: disabled,
    onClick: onClick,
    onMouseEnter: () => setH(true),
    onMouseLeave: () => setH(false)
  }, icon, children);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Card.jsx
try { (() => {
function Card({
  title,
  action,
  children,
  pattern,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-card)',
      border: '1px solid var(--border-subtle)',
      borderRadius: 'var(--radius-md)',
      boxShadow: 'var(--shadow-card)',
      overflow: 'hidden',
      ...style
    }
  }, title && /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: '14px 18px',
      borderBottom: '1px solid var(--border-subtle)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 700,
      fontSize: 15.5
    }
  }, title), action), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 18
    }
  }, children), pattern && /*#__PURE__*/React.createElement("div", {
    style: {
      height: 10,
      background: 'url(assets/pattern-band-4k.png) repeat-x',
      backgroundSize: 'auto 100%',
      opacity: .9
    }
  }));
}
Object.assign(__ds_scope, { Card });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Card.jsx", error: String((e && e.message) || e) }); }

// components/core/Checkbox.jsx
try { (() => {
function Checkbox({
  label,
  checked,
  onChange,
  disabled,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 9,
      cursor: disabled ? 'not-allowed' : 'pointer',
      fontSize: 14.5,
      opacity: disabled ? 0.45 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 18,
      height: 18,
      borderRadius: 4,
      border: '2px solid ' + (checked ? 'var(--cnc-red)' : '#B9B9B9'),
      background: checked ? 'var(--cnc-red)' : '#fff',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'all var(--dur-fast)',
      flex: 'none'
    }
  }, checked && /*#__PURE__*/React.createElement("svg", {
    width: "11",
    height: "9",
    viewBox: "0 0 11 9"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M1 4.5 4 7.5 10 1",
    stroke: "#fff",
    strokeWidth: "2.2",
    fill: "none"
  }))), /*#__PURE__*/React.createElement("input", {
    type: "checkbox",
    checked: checked,
    disabled: disabled,
    onChange: onChange,
    style: {
      display: 'none'
    }
  }), label);
}
Object.assign(__ds_scope, { Checkbox });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Checkbox.jsx", error: String((e && e.message) || e) }); }

// components/core/IconButton.jsx
try { (() => {
function IconButton({
  label,
  children,
  onClick,
  variant = 'ghost',
  style
}) {
  const [h, setH] = React.useState(false);
  const v = variant === 'solid' ? {
    background: 'var(--cnc-red)',
    color: '#fff'
  } : {
    background: h ? 'var(--surface-panel)' : 'transparent',
    color: 'var(--cnc-charcoal)'
  };
  return /*#__PURE__*/React.createElement("button", {
    "aria-label": label,
    title: label,
    onClick: onClick,
    onMouseEnter: () => setH(true),
    onMouseLeave: () => setH(false),
    style: {
      width: 36,
      height: 36,
      borderRadius: 'var(--radius-sm)',
      border: 'none',
      cursor: 'pointer',
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'background var(--dur-fast)',
      ...(variant === 'solid' && h ? {
        background: 'var(--red-dark)',
        color: '#fff'
      } : v),
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { IconButton });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/IconButton.jsx", error: String((e && e.message) || e) }); }

// components/core/Input.jsx
try { (() => {
function Input({
  label,
  hint,
  error,
  type = 'text',
  value,
  onChange,
  placeholder,
  textarea,
  style
}) {
  const [f, setF] = React.useState(false);
  const border = error ? 'var(--cnc-red)' : f ? 'var(--cnc-charcoal)' : 'var(--border-subtle)';
  const shared = {
    fontFamily: 'var(--font-body)',
    fontSize: 15,
    padding: '10px 12px',
    borderRadius: 'var(--radius-sm)',
    border: '1px solid ' + border,
    outline: 'none',
    width: '100%',
    boxSizing: 'border-box',
    boxShadow: f ? 'var(--focus-ring)' : 'none',
    transition: 'box-shadow var(--dur-fast)',
    background: '#fff',
    color: 'var(--text-body)'
  };
  const T = textarea ? /*#__PURE__*/React.createElement("textarea", {
    rows: 3,
    style: {
      ...shared,
      resize: 'vertical'
    },
    value: value,
    placeholder: placeholder,
    onChange: onChange,
    onFocus: () => setF(true),
    onBlur: () => setF(false)
  }) : /*#__PURE__*/React.createElement("input", {
    type: type,
    style: shared,
    value: value,
    placeholder: placeholder,
    onChange: onChange,
    onFocus: () => setF(true),
    onBlur: () => setF(false)
  });
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'block',
      ...style
    }
  }, label && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 13,
      marginBottom: 6
    }
  }, label), T, (error || hint) && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      marginTop: 5,
      color: error ? 'var(--cnc-red)' : 'var(--text-muted)'
    }
  }, error || hint));
}
Object.assign(__ds_scope, { Input });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Input.jsx", error: String((e && e.message) || e) }); }

// components/core/Radio.jsx
try { (() => {
function Radio({
  label,
  checked,
  onChange,
  name,
  disabled,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 9,
      cursor: disabled ? 'not-allowed' : 'pointer',
      fontSize: 14.5,
      opacity: disabled ? 0.45 : 1,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 18,
      height: 18,
      borderRadius: '50%',
      border: '2px solid ' + (checked ? 'var(--cnc-red)' : '#B9B9B9'),
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      transition: 'all var(--dur-fast)',
      flex: 'none'
    }
  }, checked && /*#__PURE__*/React.createElement("span", {
    style: {
      width: 9,
      height: 9,
      borderRadius: '50%',
      background: 'var(--cnc-red)'
    }
  })), /*#__PURE__*/React.createElement("input", {
    type: "radio",
    name: name,
    checked: checked,
    disabled: disabled,
    onChange: onChange,
    style: {
      display: 'none'
    }
  }), label);
}
Object.assign(__ds_scope, { Radio });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Radio.jsx", error: String((e && e.message) || e) }); }

// components/core/Select.jsx
try { (() => {
function Select({
  label,
  options = [],
  value,
  onChange,
  style
}) {
  const [f, setF] = React.useState(false);
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'block',
      ...style
    }
  }, label && /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 13,
      marginBottom: 6
    }
  }, label), /*#__PURE__*/React.createElement("select", {
    value: value,
    onChange: onChange,
    onFocus: () => setF(true),
    onBlur: () => setF(false),
    style: {
      fontFamily: 'var(--font-body)',
      fontSize: 15,
      padding: '10px 12px',
      borderRadius: 'var(--radius-sm)',
      border: '1px solid ' + (f ? 'var(--cnc-charcoal)' : 'var(--border-subtle)'),
      outline: 'none',
      width: '100%',
      boxSizing: 'border-box',
      background: '#fff',
      color: 'var(--text-body)',
      boxShadow: f ? 'var(--focus-ring)' : 'none'
    }
  }, options.map(o => /*#__PURE__*/React.createElement("option", {
    key: o.value ?? o,
    value: o.value ?? o
  }, o.label ?? o))));
}
Object.assign(__ds_scope, { Select });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Select.jsx", error: String((e && e.message) || e) }); }

// components/core/StatusChip.jsx
try { (() => {
function StatusChip({
  status = 'pending',
  style
}) {
  const m = {
    ok: {
      c: 'var(--cnc-green)',
      bg: 'var(--green-tint)',
      t: 'Checked in'
    },
    pending: {
      c: '#7a5600',
      bg: 'var(--yellow-tint)',
      t: 'Pending'
    },
    missed: {
      c: 'var(--red-dark)',
      bg: 'var(--red-tint)',
      t: 'Missed'
    },
    leave: {
      c: 'var(--cnc-blue)',
      bg: 'var(--blue-tint)',
      t: 'On leave'
    }
  }[status];
  return /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 12,
      padding: '4px 11px',
      borderRadius: 999,
      background: m.bg,
      color: m.c,
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 7,
      height: 7,
      borderRadius: '50%',
      background: m.c
    }
  }), m.t);
}
Object.assign(__ds_scope, { StatusChip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/StatusChip.jsx", error: String((e && e.message) || e) }); }

// components/core/Switch.jsx
try { (() => {
function Switch({
  label,
  checked,
  onChange,
  style
}) {
  return /*#__PURE__*/React.createElement("label", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 10,
      cursor: 'pointer',
      fontSize: 14.5,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    onClick: () => onChange && onChange(!checked),
    style: {
      width: 38,
      height: 22,
      borderRadius: 999,
      background: checked ? 'var(--cnc-green)' : '#C9C9C9',
      position: 'relative',
      transition: 'background var(--dur-base) var(--ease-standard)',
      flex: 'none'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      top: 2,
      left: checked ? 18 : 2,
      width: 18,
      height: 18,
      borderRadius: '50%',
      background: '#fff',
      boxShadow: '0 1px 3px rgba(0,0,0,.3)',
      transition: 'left var(--dur-base) var(--ease-standard)'
    }
  })), label);
}
Object.assign(__ds_scope, { Switch });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Switch.jsx", error: String((e && e.message) || e) }); }

// components/core/Tabs.jsx
try { (() => {
function Tabs({
  tabs = [],
  active,
  onChange,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 4,
      borderBottom: '1px solid var(--border-subtle)',
      ...style
    }
  }, tabs.map(t => {
    const on = t === active;
    return /*#__PURE__*/React.createElement("button", {
      key: t,
      onClick: () => onChange && onChange(t),
      style: {
        fontFamily: 'var(--font-heading)',
        fontWeight: 600,
        fontSize: 14,
        padding: '10px 16px',
        border: 'none',
        background: 'none',
        cursor: 'pointer',
        color: on ? 'var(--cnc-red)' : 'var(--text-muted)',
        borderBottom: on ? '2.5px solid var(--cnc-red)' : '2.5px solid transparent',
        marginBottom: -1,
        transition: 'color var(--dur-fast)'
      }
    }, t);
  }));
}
Object.assign(__ds_scope, { Tabs });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Tabs.jsx", error: String((e && e.message) || e) }); }

// components/core/Tag.jsx
try { (() => {
function Tag({
  children,
  onRemove,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 13,
      padding: '5px 10px',
      borderRadius: 'var(--radius-sm)',
      background: '#fff',
      border: '1px solid var(--border-subtle)',
      display: 'inline-flex',
      alignItems: 'center',
      gap: 6,
      ...style
    }
  }, children, onRemove && /*#__PURE__*/React.createElement("button", {
    onClick: onRemove,
    style: {
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      color: 'var(--text-muted)',
      fontSize: 14,
      lineHeight: 1,
      padding: 0
    }
  }, "\xD7"));
}
Object.assign(__ds_scope, { Tag });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Tag.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Dialog.jsx
try { (() => {
function Dialog({
  open,
  title,
  children,
  footer,
  onClose
}) {
  if (!open) return null;
  return /*#__PURE__*/React.createElement("div", {
    onClick: onClose,
    style: {
      position: 'fixed',
      inset: 0,
      background: 'rgba(0,0,0,.45)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      zIndex: 100
    }
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => e.stopPropagation(),
    style: {
      background: '#fff',
      borderRadius: 'var(--radius-lg)',
      boxShadow: 'var(--shadow-raised)',
      width: 'min(440px,92vw)',
      overflow: 'hidden'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: 5,
      background: 'var(--cnc-red)'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '18px 22px 0',
      display: 'flex',
      justifyContent: 'space-between',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 700,
      fontSize: 17
    }
  }, title), /*#__PURE__*/React.createElement("button", {
    onClick: onClose,
    style: {
      border: 'none',
      background: 'none',
      fontSize: 20,
      cursor: 'pointer',
      color: 'var(--text-muted)'
    }
  }, "\xD7")), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 22px 20px',
      fontSize: 14.5,
      lineHeight: 1.55
    }
  }, children), footer && /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '0 22px 20px',
      display: 'flex',
      gap: 10,
      justifyContent: 'flex-end'
    }
  }, footer)));
}
Object.assign(__ds_scope, { Dialog });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Dialog.jsx", error: String((e && e.message) || e) }); }

// components/feedback/Toast.jsx
try { (() => {
function Toast({
  tone = 'success',
  children,
  style
}) {
  const t = {
    success: {
      c: 'var(--cnc-green)'
    },
    info: {
      c: 'var(--cnc-blue)'
    },
    warning: {
      c: '#7a5600'
    },
    danger: {
      c: 'var(--cnc-red)'
    }
  }[tone];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--cnc-charcoal)',
      color: '#fff',
      borderRadius: 'var(--radius-md)',
      boxShadow: 'var(--shadow-raised)',
      padding: '12px 16px',
      display: 'inline-flex',
      alignItems: 'center',
      gap: 10,
      fontSize: 14,
      ...style
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      width: 8,
      height: 8,
      borderRadius: '50%',
      background: t.c,
      boxShadow: '0 0 0 3px rgba(255,255,255,.12)'
    }
  }), children);
}
Object.assign(__ds_scope, { Toast });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/feedback/Toast.jsx", error: String((e && e.message) || e) }); }

// ui_kits/checkin_app/screens.jsx
try { (() => {
const {
  Button,
  Input,
  Select,
  Checkbox,
  Radio,
  Switch,
  Card,
  Badge,
  Tabs,
  StatusChip,
  Dialog,
  Toast,
  PulseLine
} = window.CareNetConsultantsDesignSystem_7580a9;
function AppHeader({
  title,
  onBack
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: '#fff',
      borderBottom: '1px solid var(--border-subtle)',
      padding: '14px 18px',
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, onBack && /*#__PURE__*/React.createElement("button", {
    onClick: onBack,
    style: {
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      fontSize: 18,
      color: 'var(--cnc-charcoal)',
      padding: 0
    }
  }, "\u2039"), /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-horizontal.png",
    style: {
      height: 26
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      marginLeft: 'auto',
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 12.5,
      color: 'var(--text-muted)'
    }
  }, title));
}
function Welcome({
  onStart,
  onTeam
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--cnc-red)',
      color: '#fff',
      padding: '28px 22px 20px'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/logo-stacked.png",
    style: {
      width: 96,
      background: '#fff',
      borderRadius: 10,
      padding: '8px 10px'
    }
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-display)',
      fontSize: 34,
      letterSpacing: '.02em',
      lineHeight: 1.05,
      marginTop: 16
    }
  }, "Good morning, Thandi"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14,
      opacity: .92,
      marginTop: 6
    }
  }, "Ready to check in? Three quick questions."), /*#__PURE__*/React.createElement("img", {
    src: "../../assets/pulse/pulse-standard.png",
    style: {
      height: 52,
      marginTop: 14,
      filter: "brightness(0) invert(1)"
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 20,
      display: 'flex',
      flexDirection: 'column',
      gap: 14,
      flex: 1
    }
  }, /*#__PURE__*/React.createElement(Card, {
    title: "Today, Wednesday 6 August"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 700,
      fontSize: 15
    }
  }, "Daily check-in"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: 'var(--text-muted)',
      marginTop: 3
    }
  }, "Closes 17:00 \xB7 takes under a minute")), /*#__PURE__*/React.createElement(StatusChip, {
    status: "pending"
  })), /*#__PURE__*/React.createElement(Button, {
    style: {
      width: '100%',
      justifyContent: 'center',
      marginTop: 16
    },
    onClick: onStart
  }, "Check in now")), /*#__PURE__*/React.createElement(Card, {
    title: "This week"
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8
    }
  }, ['Mo', 'Tu', 'We', 'Th', 'Fr'].map((d, i) => /*#__PURE__*/React.createElement("div", {
    key: d,
    style: {
      flex: 1,
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 11.5,
      color: 'var(--text-muted)',
      marginBottom: 5
    }
  }, d), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 34,
      borderRadius: 8,
      background: i < 2 ? 'var(--green-tint)' : 'var(--surface-panel)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      color: i < 2 ? 'var(--cnc-green)' : '#C4C4C4',
      fontWeight: 700,
      fontSize: 14
    }
  }, i < 2 ? '✓' : '·'))))), /*#__PURE__*/React.createElement("button", {
    onClick: onTeam,
    style: {
      border: 'none',
      background: 'none',
      cursor: 'pointer',
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 13.5,
      color: 'var(--cnc-red)',
      padding: 6
    }
  }, "View my team")), /*#__PURE__*/React.createElement("div", {
    style: {
      height: 12,
      background: 'url(../../assets/pattern-band-4k.png) repeat-x',
      backgroundSize: 'auto 100%'
    }
  }));
}
function CheckinFlow({
  onDone,
  onBack
}) {
  const [step, setStep] = React.useState(0);
  const [mood, setMood] = React.useState('Good');
  const [fit, setFit] = React.useState(true);
  const [ppe, setPpe] = React.useState(true);
  const [blocker, setBlocker] = React.useState('');
  const [confirm, setConfirm] = React.useState(false);
  const steps = ['Wellbeing', 'Readiness', 'Blockers'];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%'
    }
  }, /*#__PURE__*/React.createElement(AppHeader, {
    title: 'Step ' + (step + 1) + ' of 3',
    onBack: step === 0 ? onBack : () => setStep(step - 1)
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 6,
      padding: '14px 20px 0'
    }
  }, steps.map((s, i) => /*#__PURE__*/React.createElement("div", {
    key: s,
    style: {
      flex: 1,
      height: 4,
      borderRadius: 2,
      background: i <= step ? 'var(--cnc-red)' : 'var(--surface-panel)'
    }
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: 20,
      flex: 1,
      display: 'flex',
      flexDirection: 'column',
      gap: 16
    }
  }, step === 0 && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 800,
      fontSize: 22
    }
  }, "How are you feeling today?"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 12
    }
  }, ['Very good', 'Good', 'Okay', 'Struggling'].map(m => /*#__PURE__*/React.createElement(Radio, {
    key: m,
    name: "mood",
    label: m,
    checked: mood === m,
    onChange: () => setMood(m)
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 13,
      color: 'var(--text-muted)'
    }
  }, "Your answer goes to your team lead only. I am because we are.")), step === 1 && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 800,
      fontSize: 22
    }
  }, "Are you ready for your shift?"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement(Checkbox, {
    label: "I am fit for duty",
    checked: fit,
    onChange: () => setFit(!fit)
  }), /*#__PURE__*/React.createElement(Checkbox, {
    label: "My PPE is complete and in good condition",
    checked: ppe,
    onChange: () => setPpe(!ppe)
  })), /*#__PURE__*/React.createElement(Select, {
    label: "Site today",
    options: ['Johannesburg', 'Cape Town', 'Durban', 'Client site']
  })), step === 2 && /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 800,
      fontSize: 22
    }
  }, "Anything blocking your work?"), /*#__PURE__*/React.createElement(Input, {
    textarea: true,
    label: "Blockers or concerns",
    placeholder: "Optional. Equipment, transport, workload\u2026",
    value: blocker,
    onChange: e => setBlocker(e.target.value)
  }), /*#__PURE__*/React.createElement(Switch, {
    label: "Notify my team lead immediately",
    checked: true,
    onChange: () => {}
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'auto'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    style: {
      width: '100%',
      justifyContent: 'center'
    },
    onClick: () => step < 2 ? setStep(step + 1) : setConfirm(true)
  }, step < 2 ? 'Continue' : 'Submit check-in'))), /*#__PURE__*/React.createElement(Dialog, {
    open: confirm,
    title: "Submit check-in?",
    onClose: () => setConfirm(false),
    footer: /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
      variant: "secondary",
      size: "sm",
      onClick: () => setConfirm(false)
    }, "Not yet"), /*#__PURE__*/React.createElement(Button, {
      size: "sm",
      onClick: onDone
    }, "Submit"))
  }, "You can edit your answers until 17:00 today."));
}
function Done({
  onHome
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%',
      alignItems: 'center',
      justifyContent: 'center',
      padding: 28,
      textAlign: 'center',
      gap: 14
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 64,
      height: 64,
      borderRadius: '50%',
      background: 'var(--green-tint)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }
  }, /*#__PURE__*/React.createElement("svg", {
    width: "28",
    height: "22",
    viewBox: "0 0 28 22"
  }, /*#__PURE__*/React.createElement("path", {
    d: "M2 12 10 20 26 2",
    stroke: "var(--cnc-green)",
    strokeWidth: "4",
    fill: "none",
    strokeLinecap: "round"
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-display)',
      fontSize: 36,
      letterSpacing: '.02em',
      lineHeight: 1.05
    }
  }, "Thank you, Thandi"), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 14.5,
      color: 'var(--text-muted)',
      maxWidth: 260
    }
  }, "Your check-in is logged and your team lead has been notified."), /*#__PURE__*/React.createElement("img", {
    src: "../../assets/pulse/pulse-heart-red.png",
    style: {
      height: 64
    }
  }), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    onClick: onHome
  }, "Back to home"));
}
function Team({
  onBack
}) {
  const [tab, setTab] = React.useState('Today');
  const people = [{
    n: 'Thandi Mokoena',
    r: 'Field consultant',
    s: 'ok'
  }, {
    n: 'Sipho Dlamini',
    r: 'OHS practitioner',
    s: 'ok'
  }, {
    n: 'Lerato Nkosi',
    r: 'Admin coordinator',
    s: 'pending'
  }, {
    n: 'Johan van Wyk',
    r: 'Field consultant',
    s: 'missed'
  }, {
    n: 'Naledi Khumalo',
    r: 'Wellness nurse',
    s: 'leave'
  }];
  return /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      flexDirection: 'column',
      height: '100%'
    }
  }, /*#__PURE__*/React.createElement(AppHeader, {
    title: "Team view",
    onBack: onBack
  }), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '16px 20px 0'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 800,
      fontSize: 20
    }
  }, "Occupational Health Team"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      marginTop: 10
    }
  }, /*#__PURE__*/React.createElement(Badge, {
    tone: "green"
  }, "3 checked in"), /*#__PURE__*/React.createElement(Badge, {
    tone: "yellow"
  }, "1 pending"), /*#__PURE__*/React.createElement(Badge, {
    tone: "red"
  }, "1 missed")), /*#__PURE__*/React.createElement(Tabs, {
    tabs: ['Today', 'This week'],
    active: tab,
    onChange: setTab,
    style: {
      marginTop: 14
    }
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      padding: '12px 20px',
      display: 'flex',
      flexDirection: 'column',
      gap: 10,
      overflow: 'auto'
    }
  }, people.map(p => /*#__PURE__*/React.createElement("div", {
    key: p.n,
    style: {
      background: '#fff',
      border: '1px solid var(--border-subtle)',
      borderRadius: 'var(--radius-md)',
      padding: '12px 14px',
      display: 'flex',
      alignItems: 'center',
      gap: 12
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      width: 38,
      height: 38,
      borderRadius: '50%',
      background: 'var(--surface-panel)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'var(--font-heading)',
      fontWeight: 700,
      fontSize: 13,
      color: 'var(--text-muted)',
      flex: 'none'
    }
  }, p.n.split(' ').map(x => x[0]).join('')), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontFamily: 'var(--font-heading)',
      fontWeight: 600,
      fontSize: 14
    }
  }, p.n), /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 12,
      color: 'var(--text-muted)'
    }
  }, p.r)), /*#__PURE__*/React.createElement(StatusChip, {
    status: p.s
  })))));
}
Object.assign(window, {
  AppHeader,
  Welcome,
  CheckinFlow,
  Done,
  Team
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/checkin_app/screens.jsx", error: String((e && e.message) || e) }); }

__ds_ns.Logo = __ds_scope.Logo;

__ds_ns.PulseLine = __ds_scope.PulseLine;

__ds_ns.Badge = __ds_scope.Badge;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Card = __ds_scope.Card;

__ds_ns.Checkbox = __ds_scope.Checkbox;

__ds_ns.IconButton = __ds_scope.IconButton;

__ds_ns.Input = __ds_scope.Input;

__ds_ns.Radio = __ds_scope.Radio;

__ds_ns.Select = __ds_scope.Select;

__ds_ns.StatusChip = __ds_scope.StatusChip;

__ds_ns.Switch = __ds_scope.Switch;

__ds_ns.Tabs = __ds_scope.Tabs;

__ds_ns.Tag = __ds_scope.Tag;

__ds_ns.Dialog = __ds_scope.Dialog;

__ds_ns.Toast = __ds_scope.Toast;

})();
