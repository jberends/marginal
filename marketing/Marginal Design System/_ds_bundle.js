/* @ds-bundle: {"format":4,"namespace":"MarginalDesignSystem_dac766","components":[{"name":"MarkdownDoc","sourcePath":"components/app/MarkdownDoc.jsx"},{"name":"TabBar","sourcePath":"components/app/TabBar.jsx"},{"name":"WindowChrome","sourcePath":"components/app/WindowChrome.jsx"},{"name":"CodeCard","sourcePath":"components/content/CodeCard.jsx"},{"name":"FeatureCard","sourcePath":"components/content/FeatureCard.jsx"},{"name":"ScreenshotFrame","sourcePath":"components/content/ScreenshotFrame.jsx"},{"name":"Button","sourcePath":"components/core/Button.jsx"},{"name":"Chip","sourcePath":"components/core/Chip.jsx"},{"name":"KeyCap","sourcePath":"components/core/KeyCap.jsx"},{"name":"Shortcut","sourcePath":"components/core/KeyCap.jsx"},{"name":"Footer","sourcePath":"components/navigation/Footer.jsx"},{"name":"NavBar","sourcePath":"components/navigation/NavBar.jsx"}],"sourceHashes":{"components/app/MarkdownDoc.jsx":"5c1f409a5905","components/app/TabBar.jsx":"9f8c52cb2c4d","components/app/WindowChrome.jsx":"a68d41336971","components/content/CodeCard.jsx":"39fc699c46c9","components/content/FeatureCard.jsx":"34e05829d925","components/content/ScreenshotFrame.jsx":"d88f0eb26920","components/core/Button.jsx":"ebd0d20e7512","components/core/Chip.jsx":"3cd653470341","components/core/KeyCap.jsx":"c4dcfae607dd","components/navigation/Footer.jsx":"230c2cfd5d08","components/navigation/NavBar.jsx":"77124edf05d2","ui_kits/app/EditorApp.jsx":"5d67254ef0f7","ui_kits/app/documents.js":"6c1b1001e09e","ui_kits/site/Sections.jsx":"54292c4c0fdb"},"inlinedExternals":[],"unexposedExports":[]} */

(() => {

const __ds_ns = (window.MarginalDesignSystem_dac766 = window.MarginalDesignSystem_dac766 || {});

const __ds_scope = {};

(__ds_ns.__errors = __ds_ns.__errors || []);

// components/app/TabBar.jsx
try { (() => {
function TabBar({
  tabs = [],
  activeId,
  onSelect,
  onClose,
  onNew,
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      height: 'var(--tabbar-h)',
      flex: '0 0 auto',
      display: 'flex',
      alignItems: 'stretch',
      background: 'var(--surface-panel)',
      borderBottom: '1px solid var(--border-hairline)',
      ...style
    }
  }, tabs.map((t, i) => {
    const on = t.id === activeId;
    return /*#__PURE__*/React.createElement("div", {
      key: t.id,
      onClick: () => onSelect && onSelect(t.id),
      style: {
        display: 'flex',
        alignItems: 'center',
        gap: 'var(--space-2)',
        padding: '0 var(--space-3)',
        minWidth: 130,
        maxWidth: 220,
        cursor: 'default',
        position: 'relative',
        borderRight: '1px solid var(--border-hairline)',
        background: on ? 'var(--surface-page)' : 'transparent',
        transition: 'background var(--dur-fast) var(--ease-standard)'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        flex: 1,
        fontSize: 'var(--text-2xs)',
        fontWeight: on ? 'var(--weight-medium)' : 'var(--weight-regular)',
        color: on ? 'var(--text-heading)' : 'var(--text-muted)',
        whiteSpace: 'nowrap',
        overflow: 'hidden',
        textOverflow: 'ellipsis'
      }
    }, t.dirty ? '• ' : '', t.title), /*#__PURE__*/React.createElement("span", {
      style: {
        fontSize: 'var(--text-3xs)',
        color: 'var(--text-subtle)'
      }
    }, "\u2318", i + 1), onClose && /*#__PURE__*/React.createElement("span", {
      onClick: e => {
        e.stopPropagation();
        onClose(t.id);
      },
      style: {
        fontSize: 'var(--text-2xs)',
        color: 'var(--text-subtle)',
        cursor: 'pointer',
        lineHeight: 1
      }
    }, "\xD7"));
  }), onNew && /*#__PURE__*/React.createElement("div", {
    onClick: onNew,
    style: {
      display: 'flex',
      alignItems: 'center',
      padding: '0 var(--space-4)',
      fontSize: 'var(--text-sm)',
      color: 'var(--text-subtle)',
      cursor: 'pointer'
    }
  }, "+"));
}
Object.assign(__ds_scope, { TabBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/app/TabBar.jsx", error: String((e && e.message) || e) }); }

// components/app/WindowChrome.jsx
try { (() => {
function Light({
  color
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      width: 12,
      height: 12,
      borderRadius: '50%',
      background: color,
      display: 'block'
    }
  });
}
function WindowChrome({
  title,
  subtitle,
  theme = 'light',
  toolbar,
  tabs,
  height,
  style,
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    "data-theme": theme,
    style: {
      background: 'var(--surface-page)',
      color: 'var(--text-body)',
      fontFamily: 'var(--font-ui)',
      display: 'flex',
      flexDirection: 'column',
      height: height || '100%',
      overflow: 'hidden',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      height: 'var(--chrome-h)',
      flex: '0 0 auto',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-3)',
      padding: '0 var(--space-4)',
      background: 'var(--surface-chrome)',
      borderBottom: '1px solid var(--border-hairline)'
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 8,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement(Light, {
    color: "#FF5F57"
  }), /*#__PURE__*/React.createElement(Light, {
    color: "#FEBC2E"
  }), /*#__PURE__*/React.createElement(Light, {
    color: "#28C840"
  })), /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      textAlign: 'center',
      minWidth: 0
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 'var(--text-xs)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--text-heading)',
      whiteSpace: 'nowrap',
      overflow: 'hidden',
      textOverflow: 'ellipsis'
    }
  }, title), subtitle && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 'var(--text-3xs)',
      color: 'var(--text-subtle)'
    }
  }, subtitle)), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-2)',
      minWidth: 76,
      justifyContent: 'flex-end'
    }
  }, toolbar)), tabs, /*#__PURE__*/React.createElement("div", {
    style: {
      flex: 1,
      minHeight: 0,
      overflow: 'auto',
      background: 'var(--surface-page)'
    }
  }, children));
}
Object.assign(__ds_scope, { WindowChrome });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/app/WindowChrome.jsx", error: String((e && e.message) || e) }); }

// components/content/CodeCard.jsx
try { (() => {
const TOK = {
  k: 'var(--syn-keyword)',
  s: 'var(--syn-string)',
  n: 'var(--syn-number)',
  c: 'var(--syn-comment)',
  f: 'var(--syn-func)',
  p: 'var(--syn-punct)'
};
function CodeCard({
  lang = 'swift',
  lines = [],
  filename,
  copyable = true,
  style
}) {
  const [copied, setCopied] = React.useState(false);
  return /*#__PURE__*/React.createElement("div", {
    style: {
      background: 'var(--surface-code)',
      border: '1px solid var(--border-hairline)',
      borderRadius: 'var(--radius-card)',
      overflow: 'hidden',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      padding: 'var(--space-2) var(--space-3) var(--space-2) var(--space-4)',
      borderBottom: '1px solid var(--border-hairline)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontFamily: 'var(--font-code)',
      fontSize: 'var(--text-3xs)',
      color: 'var(--text-subtle)',
      letterSpacing: 'var(--tracking-wide)'
    }
  }, filename || lang), copyable && /*#__PURE__*/React.createElement("button", {
    onClick: () => {
      setCopied(true);
      setTimeout(() => setCopied(false), 1200);
    },
    style: {
      font: 'inherit',
      fontFamily: 'var(--font-ui)',
      fontSize: 'var(--text-3xs)',
      color: copied ? 'var(--accent)' : 'var(--text-subtle)',
      background: 'transparent',
      border: 0,
      cursor: 'pointer',
      padding: '2px 4px',
      transition: 'color var(--dur-fast) var(--ease-standard)'
    }
  }, copied ? 'Copied' : 'Copy')), /*#__PURE__*/React.createElement("pre", {
    style: {
      margin: 0,
      padding: 'var(--space-4)',
      overflowX: 'auto',
      fontFamily: 'var(--font-code)',
      fontSize: 'var(--text-xs)',
      lineHeight: 1.65,
      color: 'var(--text-body)'
    }
  }, /*#__PURE__*/React.createElement("code", null, lines.map((ln, i) => /*#__PURE__*/React.createElement("div", {
    key: i,
    style: {
      minHeight: '1.65em',
      whiteSpace: 'pre'
    }
  }, (Array.isArray(ln) ? ln : [{
    v: ln
  }]).map((tk, j) => /*#__PURE__*/React.createElement("span", {
    key: j,
    style: {
      color: tk.t ? TOK[tk.t] : 'inherit'
    }
  }, tk.v)))))));
}
Object.assign(__ds_scope, { CodeCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/content/CodeCard.jsx", error: String((e && e.message) || e) }); }

// components/app/MarkdownDoc.jsx
try { (() => {
const H = {
  1: {
    fontSize: '30px',
    mt: 'var(--space-6)'
  },
  2: {
    fontSize: '24px',
    mt: 'var(--space-6)'
  },
  3: {
    fontSize: '20px',
    mt: 'var(--space-5)'
  }
};

/* Markers sit in the left gutter so the text column never shifts when the caret moves. */
function Marker({
  children,
  visible
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      position: 'absolute',
      right: '100%',
      paddingRight: '.25em',
      fontWeight: 'var(--weight-regular)',
      color: 'var(--text-subtle)',
      opacity: visible ? 1 : 0,
      pointerEvents: 'none',
      transition: 'opacity var(--dur-fast) var(--ease-standard)'
    }
  }, children);
}
function Inline({
  parts = []
}) {
  return /*#__PURE__*/React.createElement(React.Fragment, null, parts.map((p, i) => {
    if (p.code) return /*#__PURE__*/React.createElement("code", {
      key: i,
      style: {
        background: 'var(--surface-code)',
        color: 'var(--text-code)',
        padding: '1px 5px',
        borderRadius: 'var(--radius-chip)',
        fontSize: '.875em',
        border: '1px solid var(--border-hairline)'
      }
    }, p.code);
    if (p.bold) return /*#__PURE__*/React.createElement("strong", {
      key: i,
      style: {
        fontWeight: 'var(--weight-semibold)'
      }
    }, p.bold);
    if (p.link) return /*#__PURE__*/React.createElement("a", {
      key: i,
      href: "#",
      style: {
        color: 'var(--text-accent)'
      }
    }, p.link);
    return /*#__PURE__*/React.createElement("span", {
      key: i
    }, p.v);
  }));
}
function MarkdownDoc({
  blocks = [],
  cursorIndex = -1,
  maxWidth = 'var(--doc-max)',
  style
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth,
      margin: '0 auto',
      padding: 'var(--space-8) var(--space-6) var(--space-11)',
      fontSize: 'var(--text-base)',
      lineHeight: 'var(--leading-normal)',
      color: 'var(--text-body)',
      ...style
    }
  }, blocks.map((b, i) => {
    const focus = i === cursorIndex;
    if (b.type === 'h') {
      const h = H[b.level] || H[3];
      return /*#__PURE__*/React.createElement("h2", {
        key: i,
        style: {
          fontSize: h.fontSize,
          fontWeight: 'var(--weight-semibold)',
          color: 'var(--text-heading)',
          letterSpacing: 'var(--tracking-tight)',
          lineHeight: 'var(--leading-snug)',
          margin: 0,
          marginTop: i ? h.mt : 0,
          marginBottom: 'var(--space-2)',
          position: 'relative'
        }
      }, /*#__PURE__*/React.createElement(Marker, {
        visible: focus
      }, '#'.repeat(b.level)), b.text);
    }
    if (b.type === 'p') return /*#__PURE__*/React.createElement("p", {
      key: i,
      style: {
        margin: 'var(--space-3) 0'
      }
    }, /*#__PURE__*/React.createElement(Inline, {
      parts: b.parts || [{
        v: b.text
      }]
    }));
    if (b.type === 'quote') return /*#__PURE__*/React.createElement("blockquote", {
      key: i,
      style: {
        margin: 'var(--space-4) 0',
        padding: 'var(--space-1) 0 var(--space-1) var(--space-4)',
        borderLeft: '3px solid var(--border-strong)',
        color: 'var(--text-muted)'
      }
    }, b.text);
    if (b.type === 'code') return /*#__PURE__*/React.createElement(__ds_scope.CodeCard, {
      key: i,
      lang: b.lang,
      lines: b.lines,
      copyable: false,
      style: {
        margin: 'var(--space-4) 0'
      }
    });
    if (b.type === 'tasks') return /*#__PURE__*/React.createElement("ul", {
      key: i,
      style: {
        listStyle: 'none',
        margin: 'var(--space-3) 0',
        padding: 0,
        display: 'grid',
        gap: 'var(--space-2)'
      }
    }, b.items.map((it, j) => /*#__PURE__*/React.createElement("li", {
      key: j,
      style: {
        display: 'flex',
        alignItems: 'flex-start',
        gap: 'var(--space-2)'
      }
    }, /*#__PURE__*/React.createElement("span", {
      style: {
        width: 16,
        height: 16,
        marginTop: 3,
        borderRadius: 'var(--radius-xs)',
        flex: '0 0 auto',
        border: '1px solid ' + (it.done ? 'transparent' : 'var(--border-strong)'),
        background: it.done ? 'var(--accent)' : 'transparent',
        color: 'var(--accent-on)',
        fontSize: 11,
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center'
      }
    }, it.done ? '✓' : ''), /*#__PURE__*/React.createElement("span", {
      style: {
        color: it.done ? 'var(--text-subtle)' : 'var(--text-body)',
        textDecoration: it.done ? 'line-through' : 'none'
      }
    }, it.text))));
    if (b.type === 'ol') return /*#__PURE__*/React.createElement("ol", {
      key: i,
      style: {
        margin: 'var(--space-3) 0',
        paddingLeft: 'var(--space-5)',
        display: 'grid',
        gap: 'var(--space-2)'
      }
    }, b.items.map((it, j) => /*#__PURE__*/React.createElement("li", {
      key: j
    }, it)));
    if (b.type === 'table') return /*#__PURE__*/React.createElement("table", {
      key: i,
      style: {
        width: '100%',
        borderCollapse: 'collapse',
        margin: 'var(--space-4) 0',
        fontSize: 'var(--text-sm)',
        border: '1px solid var(--border-hairline)'
      }
    }, /*#__PURE__*/React.createElement("thead", null, /*#__PURE__*/React.createElement("tr", null, b.head.map((h, j) => /*#__PURE__*/React.createElement("th", {
      key: j,
      style: {
        textAlign: 'left',
        padding: '8px 12px',
        background: 'var(--surface-panel)',
        borderBottom: '1px solid var(--border-hairline)',
        borderRight: j < b.head.length - 1 ? '1px solid var(--border-hairline)' : 'none',
        fontWeight: 'var(--weight-semibold)',
        fontSize: 'var(--text-xs)',
        color: 'var(--text-heading)'
      }
    }, h)))), /*#__PURE__*/React.createElement("tbody", null, b.rows.map((r, j) => /*#__PURE__*/React.createElement("tr", {
      key: j
    }, r.map((c, k) => /*#__PURE__*/React.createElement("td", {
      key: k,
      style: {
        padding: '8px 12px',
        borderBottom: j < b.rows.length - 1 ? '1px solid var(--border-hairline)' : 'none',
        borderRight: k < r.length - 1 ? '1px solid var(--border-hairline)' : 'none',
        color: 'var(--text-body)'
      }
    }, c))))));
    if (b.type === 'hr') return /*#__PURE__*/React.createElement("hr", {
      key: i
    });
    return null;
  }));
}
Object.assign(__ds_scope, { MarkdownDoc });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/app/MarkdownDoc.jsx", error: String((e && e.message) || e) }); }

// components/content/FeatureCard.jsx
try { (() => {
function FeatureCard({
  title,
  body,
  glyph,
  shortcut,
  footer,
  elevated = false,
  style,
  children
}) {
  return /*#__PURE__*/React.createElement("article", {
    style: {
      background: 'var(--surface-card)',
      border: '1px solid var(--border-hairline)',
      borderRadius: 'var(--radius-card)',
      padding: 'var(--space-5)',
      boxShadow: elevated ? 'var(--shadow-raised)' : 'none',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-2)',
      ...style
    }
  }, glyph && /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 20,
      lineHeight: 1,
      color: 'var(--text-subtle)',
      marginBottom: 'var(--space-1)',
      fontFamily: 'var(--font-code)'
    }
  }, glyph), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'baseline',
      justifyContent: 'space-between',
      gap: 'var(--space-3)'
    }
  }, /*#__PURE__*/React.createElement("h3", {
    style: {
      fontSize: 'var(--text-base)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--text-heading)',
      letterSpacing: 'var(--tracking-snug)',
      margin: 0
    }
  }, title), shortcut), body && /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 'var(--text-sm)',
      lineHeight: 'var(--leading-relaxed)',
      color: 'var(--text-muted)',
      margin: 0
    }
  }, body), children, footer && /*#__PURE__*/React.createElement("div", {
    style: {
      marginTop: 'var(--space-2)',
      fontSize: 'var(--text-2xs)',
      color: 'var(--text-subtle)'
    }
  }, footer));
}
Object.assign(__ds_scope, { FeatureCard });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/content/FeatureCard.jsx", error: String((e && e.message) || e) }); }

// components/content/ScreenshotFrame.jsx
try { (() => {
function ScreenshotFrame({
  src,
  alt = '',
  caption,
  theme = 'light',
  style,
  children
}) {
  return /*#__PURE__*/React.createElement("figure", {
    style: {
      margin: 0,
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    "data-theme": theme,
    style: {
      borderRadius: 'var(--radius-frame)',
      overflow: 'hidden',
      background: 'var(--surface-page)',
      border: '1px solid var(--border-hairline)',
      boxShadow: 'var(--shadow-frame)'
    }
  }, children || /*#__PURE__*/React.createElement("img", {
    src: src,
    alt: alt,
    style: {
      display: 'block',
      width: '100%',
      height: 'auto'
    }
  })), caption && /*#__PURE__*/React.createElement("figcaption", {
    style: {
      marginTop: 'var(--space-3)',
      textAlign: 'center',
      fontSize: 'var(--text-2xs)',
      color: 'var(--text-subtle)'
    }
  }, caption));
}
Object.assign(__ds_scope, { ScreenshotFrame });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/content/ScreenshotFrame.jsx", error: String((e && e.message) || e) }); }

// components/core/Button.jsx
try { (() => {
function _extends() { return _extends = Object.assign ? Object.assign.bind() : function (n) { for (var e = 1; e < arguments.length; e++) { var t = arguments[e]; for (var r in t) ({}).hasOwnProperty.call(t, r) && (n[r] = t[r]); } return n; }, _extends.apply(null, arguments); }
const pad = {
  sm: '6px 12px',
  md: '9px 16px',
  lg: '12px 22px'
};
const fs = {
  sm: 'var(--text-xs)',
  md: 'var(--text-sm)',
  lg: 'var(--text-base)'
};
function Button({
  variant = 'primary',
  size = 'md',
  href,
  disabled = false,
  fullWidth = false,
  iconLeft,
  iconRight,
  onClick,
  type = 'button',
  style,
  children,
  ...rest
}) {
  const [hover, setHover] = React.useState(false);
  const [press, setPress] = React.useState(false);
  const base = {
    display: 'inline-flex',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 'var(--space-2)',
    font: 'inherit',
    fontFamily: 'var(--font-ui)',
    fontSize: fs[size],
    fontWeight: 'var(--weight-medium)',
    letterSpacing: 'var(--tracking-snug)',
    lineHeight: 1.2,
    padding: pad[size],
    borderRadius: 'var(--radius-sm)',
    border: '1px solid transparent',
    cursor: disabled ? 'default' : 'pointer',
    textDecoration: 'none',
    width: fullWidth ? '100%' : 'auto',
    opacity: disabled ? 0.4 : 1,
    transition: 'background var(--dur-base) var(--ease-standard),color var(--dur-base) var(--ease-standard),border-color var(--dur-base) var(--ease-standard),transform var(--dur-instant) var(--ease-standard)',
    transform: press && !disabled ? 'scale(0.985)' : 'none',
    whiteSpace: 'nowrap'
  };
  const skin = {
    primary: {
      background: press ? 'var(--accent-press)' : hover ? 'var(--accent-press)' : 'var(--accent)',
      color: 'var(--accent-on)'
    },
    secondary: {
      background: hover ? 'var(--surface-sunk)' : 'var(--surface-card)',
      color: 'var(--text-body)',
      borderColor: 'var(--border-hairline)',
      boxShadow: '0 1px 1px rgba(35,35,35,.03)'
    },
    ghost: {
      background: hover ? 'var(--surface-panel)' : 'transparent',
      color: 'var(--text-muted)'
    }
  }[variant];
  const Tag = href ? 'a' : 'button';
  return /*#__PURE__*/React.createElement(Tag, _extends({
    href: href,
    type: href ? undefined : type,
    disabled: href ? undefined : disabled,
    onClick: disabled ? undefined : onClick,
    onMouseEnter: () => setHover(true),
    onMouseLeave: () => {
      setHover(false);
      setPress(false);
    },
    onMouseDown: () => setPress(true),
    onMouseUp: () => setPress(false),
    style: {
      ...base,
      ...skin,
      ...style
    }
  }, rest), iconLeft, children, iconRight);
}
Object.assign(__ds_scope, { Button });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Button.jsx", error: String((e && e.message) || e) }); }

// components/core/Chip.jsx
try { (() => {
function Chip({
  tone = 'neutral',
  children,
  style
}) {
  const tones = {
    neutral: {
      background: 'var(--surface-panel)',
      color: 'var(--text-muted)',
      border: '1px solid var(--border-hairline)'
    },
    accent: {
      background: 'var(--accent-tint)',
      color: 'var(--accent)',
      border: '1px solid transparent'
    },
    code: {
      background: 'var(--surface-code)',
      color: 'var(--text-code)',
      border: '1px solid var(--border-hairline)',
      fontFamily: 'var(--font-code)'
    }
  };
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 'var(--space-1)',
      padding: '3px 8px',
      borderRadius: 'var(--radius-chip)',
      fontSize: 'var(--text-2xs)',
      fontWeight: 'var(--weight-medium)',
      lineHeight: 1.4,
      letterSpacing: 'var(--tracking-snug)',
      ...tones[tone],
      ...style
    }
  }, children);
}
Object.assign(__ds_scope, { Chip });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/Chip.jsx", error: String((e && e.message) || e) }); }

// components/core/KeyCap.jsx
try { (() => {
function KeyCap({
  children,
  size = 'md',
  style
}) {
  const s = size === 'sm' ? {
    fontSize: 'var(--text-3xs)',
    padding: '1px 5px',
    minWidth: 18
  } : {
    fontSize: 'var(--text-2xs)',
    padding: '2px 6px',
    minWidth: 22
  };
  return /*#__PURE__*/React.createElement("kbd", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      justifyContent: 'center',
      fontFamily: 'var(--font-ui)',
      fontWeight: 'var(--weight-medium)',
      color: 'var(--text-muted)',
      background: 'var(--surface-card)',
      border: '1px solid var(--border-hairline)',
      borderBottomColor: 'var(--border-strong)',
      borderRadius: 'var(--radius-chip)',
      boxShadow: 'var(--shadow-key)',
      lineHeight: 1.5,
      ...s,
      ...style
    }
  }, children);
}
function Shortcut({
  keys,
  style
}) {
  return /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'inline-flex',
      alignItems: 'center',
      gap: 'var(--space-1)',
      ...style
    }
  }, keys.map((k, i) => /*#__PURE__*/React.createElement(KeyCap, {
    key: i
  }, k)));
}
Object.assign(__ds_scope, { KeyCap, Shortcut });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/core/KeyCap.jsx", error: String((e && e.message) || e) }); }

// components/navigation/Footer.jsx
try { (() => {
function Footer({
  logoSrc,
  columns = [],
  note,
  license = 'Apache 2.0',
  author = 'Jochem Berends',
  style
}) {
  return /*#__PURE__*/React.createElement("footer", {
    style: {
      borderTop: '1px solid var(--border-hairline)',
      background: 'var(--surface-panel)',
      padding: 'var(--space-9) var(--space-5) var(--space-6)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--content-max)',
      margin: '0 auto',
      display: 'grid',
      gridTemplateColumns: 'minmax(200px,1.3fr) repeat(' + Math.max(columns.length, 1) + ',1fr)',
      gap: 'var(--space-8)'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-2)',
      marginBottom: 'var(--space-3)'
    }
  }, logoSrc && /*#__PURE__*/React.createElement("img", {
    src: logoSrc,
    alt: "",
    width: 22,
    height: 22,
    style: {
      display: 'block',
      borderRadius: 5
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--text-sm)',
      fontWeight: 'var(--weight-semibold)',
      color: 'var(--text-heading)'
    }
  }, "Marginal")), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 'var(--text-xs)',
      color: 'var(--text-muted)',
      maxWidth: '32ch',
      lineHeight: 'var(--leading-relaxed)'
    }
  }, note || 'A native macOS markdown editor. Your files stay plain text.')), columns.map(col => /*#__PURE__*/React.createElement("div", {
    key: col.title
  }, /*#__PURE__*/React.createElement("h4", {
    style: {
      fontSize: 'var(--text-3xs)',
      fontWeight: 'var(--weight-semibold)',
      textTransform: 'uppercase',
      letterSpacing: 'var(--tracking-wide)',
      color: 'var(--text-subtle)',
      marginBottom: 'var(--space-3)'
    }
  }, col.title), /*#__PURE__*/React.createElement("ul", {
    style: {
      listStyle: 'none',
      margin: 0,
      padding: 0,
      display: 'grid',
      gap: 'var(--space-2)'
    }
  }, col.links.map(l => /*#__PURE__*/React.createElement("li", {
    key: l.label
  }, /*#__PURE__*/React.createElement("a", {
    href: l.href || '#',
    style: {
      fontSize: 'var(--text-xs)',
      color: 'var(--text-muted)',
      textDecoration: 'none'
    }
  }, l.label))))))), /*#__PURE__*/React.createElement("div", {
    style: {
      maxWidth: 'var(--content-max)',
      margin: 'var(--space-8) auto 0',
      paddingTop: 'var(--space-4)',
      borderTop: '1px solid var(--border-hairline)',
      display: 'flex',
      justifyContent: 'space-between',
      gap: 'var(--space-4)',
      fontSize: 'var(--text-3xs)',
      color: 'var(--text-subtle)'
    }
  }, /*#__PURE__*/React.createElement("span", null, license, " \xB7 Open source"), /*#__PURE__*/React.createElement("span", null, "Made by ", author)));
}
Object.assign(__ds_scope, { Footer });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/Footer.jsx", error: String((e && e.message) || e) }); }

// components/navigation/NavBar.jsx
try { (() => {
function NavBar({
  logoSrc,
  brand = 'Marginal',
  links = [],
  cta,
  onNavigate,
  active,
  style
}) {
  return /*#__PURE__*/React.createElement("header", {
    style: {
      position: 'sticky',
      top: 0,
      zIndex: 20,
      background: 'color-mix(in srgb,var(--surface-page) 88%,transparent)',
      backdropFilter: 'saturate(180%) blur(20px)',
      WebkitBackdropFilter: 'saturate(180%) blur(20px)',
      borderBottom: '1px solid var(--border-hairline)',
      ...style
    }
  }, /*#__PURE__*/React.createElement("nav", {
    style: {
      maxWidth: 'var(--content-max)',
      margin: '0 auto',
      height: 64,
      padding: '0 var(--space-5)',
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-6)'
    }
  }, /*#__PURE__*/React.createElement("a", {
    href: "#",
    onClick: e => {
      e.preventDefault();
      onNavigate && onNavigate('home');
    },
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-2)',
      textDecoration: 'none'
    }
  }, logoSrc && /*#__PURE__*/React.createElement("img", {
    src: logoSrc,
    alt: "",
    width: 26,
    height: 26,
    style: {
      display: 'block',
      borderRadius: 6
    }
  }), /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--text-base)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: 'var(--tracking-snug)',
      color: 'var(--text-heading)'
    }
  }, brand)), /*#__PURE__*/React.createElement("ul", {
    style: {
      display: 'flex',
      alignItems: 'center',
      gap: 'var(--space-5)',
      listStyle: 'none',
      margin: 0,
      padding: 0,
      marginRight: 'auto'
    }
  }, links.map(l => /*#__PURE__*/React.createElement("li", {
    key: l.id || l.label
  }, /*#__PURE__*/React.createElement("a", {
    href: l.href || '#',
    onClick: e => {
      if (onNavigate) {
        e.preventDefault();
        onNavigate(l.id || l.label);
      }
    },
    style: {
      fontSize: 'var(--text-sm)',
      fontWeight: 'var(--weight-medium)',
      textDecoration: 'none',
      color: active === (l.id || l.label) ? 'var(--text-heading)' : 'var(--text-muted)',
      transition: 'color var(--dur-fast) var(--ease-standard)'
    }
  }, l.label)))), cta && /*#__PURE__*/React.createElement(__ds_scope.Button, {
    variant: "primary",
    size: "sm",
    href: cta.href,
    onClick: cta.onClick
  }, cta.label)));
}
Object.assign(__ds_scope, { NavBar });
})(); } catch (e) { __ds_ns.__errors.push({ path: "components/navigation/NavBar.jsx", error: String((e && e.message) || e) }); }

// ui_kits/app/EditorApp.jsx
try { (() => {
const DS = () => window.MarginalDesignSystem_dac766;
function ToolbarButtons({
  theme,
  onTheme
}) {
  const {
    Button
  } = DS();
  return /*#__PURE__*/React.createElement(React.Fragment, null, /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "sm"
  }, "Copy as Markdown"), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "sm",
    onClick: onTheme
  }, theme === 'light' ? 'Dark' : 'Light'));
}
function EditorApp({
  height = 620
}) {
  const {
    WindowChrome,
    TabBar,
    MarkdownDoc,
    Shortcut
  } = DS();
  const docs = window.MARGINAL_DOCS;
  const [activeId, setActiveId] = React.useState(docs[0].id);
  const [open, setOpen] = React.useState(docs.map(d => d.id));
  const [theme, setTheme] = React.useState('light');
  const [cursor, setCursor] = React.useState({});
  const tabs = open.map(id => {
    const d = docs.find(x => x.id === id);
    return {
      id,
      title: d.title,
      dirty: d.dirty
    };
  });
  const doc = docs.find(d => d.id === activeId) || docs[0];
  const ci = cursor[activeId] === undefined ? 0 : cursor[activeId];
  return /*#__PURE__*/React.createElement(WindowChrome, {
    height: height,
    theme: theme,
    title: doc.title,
    subtitle: doc.path,
    toolbar: /*#__PURE__*/React.createElement(ToolbarButtons, {
      theme: theme,
      onTheme: () => setTheme(t => t === 'light' ? 'dark' : 'light')
    }),
    tabs: /*#__PURE__*/React.createElement(TabBar, {
      tabs: tabs,
      activeId: activeId,
      onSelect: setActiveId,
      onClose: id => {
        const rest = open.filter(x => x !== id);
        if (rest.length) {
          setOpen(rest);
          if (id === activeId) setActiveId(rest[0]);
        }
      },
      onNew: () => setOpen(docs.map(d => d.id))
    })
  }, /*#__PURE__*/React.createElement("div", {
    onClick: e => {
      const el = e.target.closest('[data-block]');
      if (el) setCursor(c => ({
        ...c,
        [activeId]: Number(el.dataset.block)
      }));
    }
  }, /*#__PURE__*/React.createElement(BlockWrap, null, /*#__PURE__*/React.createElement(MarkdownDoc, {
    blocks: doc.blocks,
    cursorIndex: ci
  }))), /*#__PURE__*/React.createElement("div", {
    style: {
      position: 'sticky',
      bottom: 0,
      display: 'flex',
      justifyContent: 'space-between',
      padding: '6px 16px',
      fontSize: 'var(--text-3xs)',
      color: 'var(--text-subtle)',
      borderTop: '1px solid var(--border-hairline)',
      background: 'var(--surface-chrome)'
    }
  }, /*#__PURE__*/React.createElement("span", null, doc.path, "/", doc.title), /*#__PURE__*/React.createElement("span", {
    style: {
      display: 'flex',
      gap: 16,
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("span", null, "Markdown"), /*#__PURE__*/React.createElement(Shortcut, {
    keys: ['⌘', '1']
  }))));
}

/* tags each rendered top-level block so clicking one moves the caret */
function BlockWrap({
  children
}) {
  const ref = React.useRef(null);
  React.useEffect(() => {
    const root = ref.current && ref.current.firstElementChild;
    if (!root) return;
    Array.from(root.children).forEach((el, i) => el.dataset.block = i);
  });
  return /*#__PURE__*/React.createElement("div", {
    ref: ref
  }, children);
}
Object.assign(window, {
  EditorApp
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/app/EditorApp.jsx", error: String((e && e.message) || e) }); }

// ui_kits/app/documents.js
try { (() => {
window.MARGINAL_DOCS = [{
  id: 'notes',
  title: 'release-notes.md',
  path: '~/Notes',
  blocks: [{
    type: 'h',
    level: 1,
    text: 'Marginal 1.4'
  }, {
    type: 'p',
    parts: [{
      v: 'Tabs land in this release. Open as many documents as you like in one window and move between them with '
    }, {
      code: '⌘1'
    }, {
      v: '–'
    }, {
      code: '⌘9'
    }, {
      v: '.'
    }]
  }, {
    type: 'h',
    level: 2,
    text: 'What changed'
  }, {
    type: 'tasks',
    items: [{
      text: 'Native macOS tab bar',
      done: true
    }, {
      text: 'Copy as Markdown / Copy as HTML',
      done: true
    }, {
      text: 'Emoji :shortcodes: in headings'
    }, {
      text: 'Per-window theme override'
    }]
  }, {
    type: 'h',
    level: 2,
    text: 'Rendering'
  }, {
    type: 'p',
    parts: [{
      v: 'Code blocks are measured against Notion pixel by pixel — '
    }, {
      bold: '10px radius'
    }, {
      v: ', warm gray fill, hairline border.'
    }]
  }, {
    type: 'code',
    lang: 'swift',
    lines: [[{
      t: 'k',
      v: 'func '
    }, {
      t: 'f',
      v: 'render'
    }, {
      v: '('
    }, {
      t: 'p',
      v: '_ '
    }, {
      v: 'doc: '
    }, {
      t: 'k',
      v: 'Document'
    }, {
      v: ') {'
    }], [{
      v: '  '
    }, {
      t: 'k',
      v: 'let '
    }, {
      v: 'measure = '
    }, {
      t: 'n',
      v: '720'
    }, {
      v: '  '
    }, {
      t: 'c',
      v: '// document column'
    }], [{
      v: '  layout.'
    }, {
      t: 'f',
      v: 'flow'
    }, {
      v: '(doc, width: measure)'
    }], [{
      v: '}'
    }]]
  }, {
    type: 'quote',
    text: 'No split pane. No raw-syntax soup. The document is the editor.'
  }, {
    type: 'table',
    head: ['Shortcut', 'Action'],
    rows: [['⌘1–⌘9', 'Switch tab'], ['⌘⇧C', 'Copy as HTML'], ['⌘T', 'New tab']]
  }]
}, {
  id: 'draft',
  title: 'essay-draft.md',
  path: '~/Writing',
  dirty: true,
  blocks: [{
    type: 'h',
    level: 1,
    text: 'On the margins'
  }, {
    type: 'p',
    text: 'A note in the margin is a second voice — quieter than the text, but reading the same line.'
  }, {
    type: 'h',
    level: 3,
    text: 'Three things'
  }, {
    type: 'ol',
    items: ['The file is the truth.', 'The rendering is a courtesy.', 'Both are yours to keep.']
  }, {
    type: 'hr'
  }, {
    type: 'p',
    parts: [{
      v: 'Filed under '
    }, {
      link: '#writing'
    }, {
      v: '.'
    }]
  }]
}, {
  id: 'readme',
  title: 'README.md',
  path: '~/src/marginal',
  blocks: [{
    type: 'h',
    level: 1,
    text: 'Marginal'
  }, {
    type: 'p',
    parts: [{
      v: 'A native macOS WYSIWYG markdown editor. Apache 2.0. '
    }, {
      code: 'brew install marginal'
    }]
  }, {
    type: 'h',
    level: 2,
    text: 'Build'
  }, {
    type: 'code',
    lang: 'bash',
    lines: [[{
      t: 'p',
      v: '$ '
    }, {
      v: 'git clone git@github.com:marginal/marginal.git'
    }], [{
      t: 'p',
      v: '$ '
    }, {
      v: 'xcodebuild -scheme Marginal'
    }]]
  }, {
    type: 'p',
    text: 'Files stay plain markdown. No database, no lock-in, works with git.'
  }]
}];
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/app/documents.js", error: String((e && e.message) || e) }); }

// ui_kits/site/Sections.jsx
try { (() => {
const DS = () => window.MarginalDesignSystem_dac766;
const Wrap = ({
  children,
  style
}) => /*#__PURE__*/React.createElement("div", {
  style: {
    maxWidth: 'var(--content-max)',
    margin: '0 auto',
    padding: '0 var(--space-6)',
    ...style
  }
}, children);
function Eyebrow({
  children
}) {
  return /*#__PURE__*/React.createElement("div", {
    style: {
      fontSize: 'var(--text-3xs)',
      textTransform: 'uppercase',
      letterSpacing: 'var(--tracking-wide)',
      color: 'var(--text-subtle)',
      fontWeight: 'var(--weight-semibold)',
      marginBottom: 'var(--space-3)'
    }
  }, children);
}
function MiniEditor({
  theme = 'light'
}) {
  const {
    WindowChrome,
    TabBar,
    MarkdownDoc,
    Button
  } = DS();
  const blocks = [{
    type: 'h',
    level: 1,
    text: 'Marginal 1.4'
  }, {
    type: 'p',
    parts: [{
      v: 'Tabs land in this release. Move between documents with '
    }, {
      code: '⌘1'
    }, {
      v: '–'
    }, {
      code: '⌘9'
    }, {
      v: '.'
    }]
  }, {
    type: 'tasks',
    items: [{
      text: 'Native macOS tab bar',
      done: true
    }, {
      text: 'Copy as HTML',
      done: true
    }, {
      text: 'Emoji :shortcodes:'
    }]
  }, {
    type: 'code',
    lang: 'swift',
    lines: [[{
      t: 'k',
      v: 'let '
    }, {
      v: 'measure = '
    }, {
      t: 'n',
      v: '720'
    }, {
      v: '  '
    }, {
      t: 'c',
      v: '// document column'
    }]]
  }, {
    type: 'quote',
    text: 'No split pane. The document is the editor.'
  }];
  return /*#__PURE__*/React.createElement(WindowChrome, {
    theme: theme,
    height: 430,
    title: "release-notes.md",
    subtitle: "~/Notes",
    toolbar: /*#__PURE__*/React.createElement(Button, {
      variant: "ghost",
      size: "sm"
    }, "Copy as HTML"),
    tabs: /*#__PURE__*/React.createElement(TabBar, {
      tabs: [{
        id: 'a',
        title: 'release-notes.md'
      }, {
        id: 'b',
        title: 'essay-draft.md',
        dirty: true
      }],
      activeId: "a"
    })
  }, /*#__PURE__*/React.createElement(MarkdownDoc, {
    blocks: blocks,
    cursorIndex: 0,
    maxWidth: "600px"
  }));
}
function Hero({
  theme,
  onTheme
}) {
  const {
    Button,
    Chip,
    ScreenshotFrame
  } = DS();
  return /*#__PURE__*/React.createElement("section", {
    style: {
      padding: 'var(--space-11) 0 var(--space-9)'
    }
  }, /*#__PURE__*/React.createElement(Wrap, {
    style: {
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement("img", {
    src: "../../assets/marginal-icon.png",
    width: "88",
    height: "88",
    alt: "",
    style: {
      display: 'block',
      margin: '0 auto var(--space-5)'
    }
  }), /*#__PURE__*/React.createElement("h1", {
    style: {
      fontSize: 'var(--text-display)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: '-0.03em',
      lineHeight: 1.05,
      margin: '0 auto',
      maxWidth: '16ch',
      color: 'var(--text-heading)'
    }
  }, "Markdown that reads the way it renders."), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 'var(--text-h3)',
      color: 'var(--text-muted)',
      lineHeight: 'var(--leading-relaxed)',
      maxWidth: 'var(--measure-narrow)',
      margin: 'var(--space-5) auto 0'
    }
  }, "A native macOS editor for plain ", /*#__PURE__*/React.createElement("code", {
    style: {
      background: 'var(--surface-code)',
      color: 'var(--text-code)',
      padding: '2px 6px',
      borderRadius: 'var(--radius-chip)',
      border: '1px solid var(--border-hairline)',
      fontSize: '.85em'
    }
  }, ".md"), " files that renders while you type \u2014 no split pane, no syntax soup."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-3)',
      justifyContent: 'center',
      marginTop: 'var(--space-6)'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "lg",
    href: "#download"
  }, "Download for macOS"), /*#__PURE__*/React.createElement(Button, {
    variant: "secondary",
    size: "lg",
    href: "#source"
  }, "View source")), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-2)',
      justifyContent: 'center',
      marginTop: 'var(--space-4)'
    }
  }, /*#__PURE__*/React.createElement(Chip, null, "Apache 2.0"), /*#__PURE__*/React.createElement(Chip, null, "Universal \xB7 Apple silicon"), /*#__PURE__*/React.createElement("button", {
    onClick: onTheme,
    style: {
      font: 'inherit',
      fontSize: 'var(--text-2xs)',
      background: 'transparent',
      border: '1px solid var(--border-hairline)',
      borderRadius: 'var(--radius-chip)',
      padding: '3px 8px',
      color: 'var(--text-muted)',
      cursor: 'pointer'
    }
  }, theme === 'light' ? 'Preview dark' : 'Preview light'))), /*#__PURE__*/React.createElement(Wrap, {
    style: {
      marginTop: 'var(--space-9)'
    }
  }, /*#__PURE__*/React.createElement(ScreenshotFrame, {
    theme: theme,
    caption: "Marginal 1.4 \u2014 one window, many documents"
  }, /*#__PURE__*/React.createElement(MiniEditor, {
    theme: theme
  }))));
}
const FEATURES = [{
  glyph: '##',
  title: 'Marks hide themselves',
  body: 'Syntax markers fade out as you type and reappear only around the cursor. The page never jumps.'
}, {
  glyph: '▤',
  title: 'Notion-grade rendering',
  body: 'Tables with real grids, rounded code cards with highlighting, checkboxes, auto-renumbered lists — measured pixel by pixel.'
}, {
  glyph: '.md',
  title: 'Plain files, always',
  body: 'No database, no lock-in. Your documents are markdown on disk and diff cleanly in git.'
}, {
  glyph: '⌘',
  title: 'Tabs in one window',
  body: 'The real macOS tab bar, with ⌘1–⌘9 to switch.',
  shortcut: ['⌘', '1']
}, {
  glyph: '⌥',
  title: 'Native AppKit',
  body: 'Instant launch, low memory. It feels like a Mac app because it is one.'
}, {
  glyph: '◑',
  title: 'Light and dark',
  body: 'Follows the system appearance, and copies out as Markdown or as HTML.',
  shortcut: ['⌘', '⇧', 'C']
}];
function Features() {
  const {
    FeatureCard,
    Shortcut
  } = DS();
  return /*#__PURE__*/React.createElement("section", {
    style: {
      padding: 'var(--space-9) 0',
      borderTop: '1px solid var(--border-hairline)'
    }
  }, /*#__PURE__*/React.createElement(Wrap, null, /*#__PURE__*/React.createElement(Eyebrow, null, "What it does"), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontSize: 'var(--text-display-sm)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: '-0.02em',
      maxWidth: '20ch',
      color: 'var(--text-heading)'
    }
  }, "Everything the file already said."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(3,1fr)',
      gap: 'var(--space-4)',
      marginTop: 'var(--space-7)'
    }
  }, FEATURES.map(ft => /*#__PURE__*/React.createElement(FeatureCard, {
    key: ft.title,
    glyph: ft.glyph,
    title: ft.title,
    body: ft.body,
    shortcut: ft.shortcut ? /*#__PURE__*/React.createElement(Shortcut, {
      keys: ft.shortcut
    }) : null
  })))));
}
function PlainText() {
  const {
    Button,
    CodeCard
  } = DS();
  return /*#__PURE__*/React.createElement("section", {
    style: {
      padding: 'var(--space-9) 0',
      background: 'var(--surface-panel)',
      borderTop: '1px solid var(--border-hairline)'
    }
  }, /*#__PURE__*/React.createElement(Wrap, {
    style: {
      display: 'grid',
      gridTemplateColumns: '1fr 1fr',
      gap: 'var(--space-8)',
      alignItems: 'center'
    }
  }, /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(Eyebrow, null, "No lock-in"), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontSize: 'var(--text-h1)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: '-0.02em',
      color: 'var(--text-heading)'
    }
  }, "What you see on the left is what sits on disk."), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 'var(--text-base)',
      color: 'var(--text-muted)',
      lineHeight: 'var(--leading-relaxed)',
      marginTop: 'var(--space-4)',
      maxWidth: '42ch'
    }
  }, "Marginal edits the file itself. Close the app and your notes are still markdown \u2014 readable in any editor, committable to any repo."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-2)',
      marginTop: 'var(--space-5)'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "secondary"
  }, "Read the docs"))), /*#__PURE__*/React.createElement(CodeCard, {
    lang: "markdown",
    filename: "release-notes.md",
    lines: [[{
      t: 'k',
      v: '# '
    }, {
      v: 'Marginal 1.4'
    }], [{
      v: ''
    }], [{
      v: 'Tabs land in this release.'
    }], [{
      v: ''
    }], [{
      t: 'k',
      v: '## '
    }, {
      v: 'What changed'
    }], [{
      t: 'p',
      v: '- [x] '
    }, {
      v: 'Native macOS tab bar'
    }], [{
      t: 'p',
      v: '- [ ] '
    }, {
      v: 'Emoji '
    }, {
      t: 's',
      v: ':shortcodes:'
    }]]
  })));
}
const KEYS = [{
  keys: ['⌘', '1'],
  label: 'Switch to tab one'
}, {
  keys: ['⌘', 'T'],
  label: 'New tab'
}, {
  keys: ['⌘', '⇧', 'C'],
  label: 'Copy as HTML'
}, {
  keys: ['⌘', '⌥', 'C'],
  label: 'Copy as Markdown'
}];
function Shortcuts() {
  const {
    Shortcut
  } = DS();
  return /*#__PURE__*/React.createElement("section", {
    style: {
      padding: 'var(--space-9) 0',
      borderTop: '1px solid var(--border-hairline)'
    }
  }, /*#__PURE__*/React.createElement(Wrap, null, /*#__PURE__*/React.createElement(Eyebrow, null, "Keyboard"), /*#__PURE__*/React.createElement("h2", {
    style: {
      fontSize: 'var(--text-h1)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: '-0.02em',
      color: 'var(--text-heading)'
    }
  }, "Hands stay where they are."), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'grid',
      gridTemplateColumns: 'repeat(2,1fr)',
      gap: 'var(--space-2) var(--space-8)',
      marginTop: 'var(--space-6)'
    }
  }, KEYS.map(k => /*#__PURE__*/React.createElement("div", {
    key: k.label,
    style: {
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'space-between',
      gap: 'var(--space-4)',
      padding: 'var(--space-3) 0',
      borderBottom: '1px solid var(--border-hairline)'
    }
  }, /*#__PURE__*/React.createElement("span", {
    style: {
      fontSize: 'var(--text-sm)',
      color: 'var(--text-body)'
    }
  }, k.label), /*#__PURE__*/React.createElement(Shortcut, {
    keys: k.keys
  }))))));
}
function Download() {
  const {
    Button
  } = DS();
  return /*#__PURE__*/React.createElement("section", {
    id: "download",
    style: {
      padding: 'var(--space-10) 0',
      borderTop: '1px solid var(--border-hairline)',
      textAlign: 'center'
    }
  }, /*#__PURE__*/React.createElement(Wrap, null, /*#__PURE__*/React.createElement("h2", {
    style: {
      fontSize: 'var(--text-display-sm)',
      fontWeight: 'var(--weight-semibold)',
      letterSpacing: '-0.02em',
      color: 'var(--text-heading)'
    }
  }, "Free, open, and yours."), /*#__PURE__*/React.createElement("p", {
    style: {
      fontSize: 'var(--text-base)',
      color: 'var(--text-muted)',
      marginTop: 'var(--space-3)'
    }
  }, "macOS 13 or later \xB7 Universal \xB7 Apache 2.0"), /*#__PURE__*/React.createElement("div", {
    style: {
      display: 'flex',
      gap: 'var(--space-3)',
      justifyContent: 'center',
      marginTop: 'var(--space-5)'
    }
  }, /*#__PURE__*/React.createElement(Button, {
    variant: "primary",
    size: "lg"
  }, "Download Marginal"), /*#__PURE__*/React.createElement(Button, {
    variant: "ghost",
    size: "lg"
  }, "Read the source"))));
}
function SiteApp() {
  const {
    NavBar,
    Footer
  } = DS();
  const [theme, setTheme] = React.useState('light');
  return /*#__PURE__*/React.createElement("div", null, /*#__PURE__*/React.createElement(NavBar, {
    logoSrc: "../../assets/marginal-icon.png",
    links: [{
      id: 'features',
      label: 'Features'
    }, {
      id: 'shortcuts',
      label: 'Shortcuts'
    }, {
      id: 'docs',
      label: 'Docs'
    }, {
      id: 'source',
      label: 'Source'
    }],
    active: "features",
    cta: {
      label: 'Download',
      href: '#download'
    }
  }), /*#__PURE__*/React.createElement(Hero, {
    theme: theme,
    onTheme: () => setTheme(t => t === 'light' ? 'dark' : 'light')
  }), /*#__PURE__*/React.createElement(Features, null), /*#__PURE__*/React.createElement(PlainText, null), /*#__PURE__*/React.createElement(Shortcuts, null), /*#__PURE__*/React.createElement(Download, null), /*#__PURE__*/React.createElement(Footer, {
    logoSrc: "../../assets/marginal-icon.png",
    columns: [{
      title: 'Product',
      links: [{
        label: 'Features'
      }, {
        label: 'Shortcuts'
      }, {
        label: 'Changelog'
      }]
    }, {
      title: 'Source',
      links: [{
        label: 'GitHub'
      }, {
        label: 'Licence'
      }, {
        label: 'Issues'
      }]
    }, {
      title: 'Elsewhere',
      links: [{
        label: 'Mastodon'
      }, {
        label: 'RSS'
      }]
    }]
  }));
}
Object.assign(window, {
  SiteApp,
  Hero,
  Features,
  PlainText,
  Shortcuts,
  Download,
  MiniEditor
});
})(); } catch (e) { __ds_ns.__errors.push({ path: "ui_kits/site/Sections.jsx", error: String((e && e.message) || e) }); }

__ds_ns.MarkdownDoc = __ds_scope.MarkdownDoc;

__ds_ns.TabBar = __ds_scope.TabBar;

__ds_ns.WindowChrome = __ds_scope.WindowChrome;

__ds_ns.CodeCard = __ds_scope.CodeCard;

__ds_ns.FeatureCard = __ds_scope.FeatureCard;

__ds_ns.ScreenshotFrame = __ds_scope.ScreenshotFrame;

__ds_ns.Button = __ds_scope.Button;

__ds_ns.Chip = __ds_scope.Chip;

__ds_ns.KeyCap = __ds_scope.KeyCap;

__ds_ns.Shortcut = __ds_scope.Shortcut;

__ds_ns.Footer = __ds_scope.Footer;

__ds_ns.NavBar = __ds_scope.NavBar;

})();
