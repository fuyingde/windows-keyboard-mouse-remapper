(() => {
  const APP_VERSION = '1.7';
  const AUTHOR_URL = 'https://www.imtr.cn/keymousetools';
  const REPOSITORY_URL = 'https://github.com/fuyingde/windows-keyboard-mouse-remapper';
  const $ = selector => document.querySelector(selector);
  document.body.classList.add('app-booting');

  const mappingList = $('#mappingList');
  const addMapping = $('#addMapping');
  const addWarning = $('#addWarning');
  const countEl = $('#count');
  const panelTitle = $('#panelTitle');
  const confirmBackdrop = $('#confirmBackdrop');
  const confirmTitle = $('#confirmTitle');
  const confirmText = $('#confirmText');
  const globalInputSwitch = $('#globalInputSwitch');
  const globalInputDisabledNote = $('#globalInputDisabledNote');
  const topMostButton = $('.win-btn.topmost');
  const titlebar = $('.titlebar');
  const windowActions = $('.window-actions');

  const localesData = readEmbeddedJson('locales-data', { defaultLocale: 'zh-CN', order: [], packs: {} });
  const bootstrap = readEmbeddedJson('app-bootstrap', { locale: localesData.defaultLocale || 'zh-CN', languageSelected: false });
  let currentLocale = localesData.packs?.[bootstrap.locale] ? bootstrap.locale : localesData.defaultLocale;
  let currentPack = localesData.packs?.[currentLocale] || { meta: {}, strings: {}, help: { sections: [] }, changelog: { entries: [] }, aboutHtml: '' };
  let helpData = currentPack.help || { sections: [] };
  let changelogData = currentPack.changelog || { entries: [] };
  let state = { mode: 'mapping', inputEnabled: true, mappings: [], settings: {} };
  let mappings = [];
  let nextMappingId = 1;
  let recording = null;
  let mappingPointerInside = false;
  let pendingConfirm = null;
  let statusTimer = null;
  let activeHelpId = '';
  const expandedHelpNodes = new Set();

  function readEmbeddedJson(id, fallback) {
    try {
      const text = document.getElementById(id)?.textContent || '';
      return text ? JSON.parse(text) : fallback;
    } catch {
      return fallback;
    }
  }

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);
  }

  function t(key, values = {}) {
    const fallback = localesData.packs?.[localesData.defaultLocale]?.strings || {};
    let text = currentPack.strings?.[key] ?? fallback[key] ?? key;
    for (const [name, value] of Object.entries(values)) text = text.replaceAll(`{${name}}`, String(value));
    return text;
  }

  function useLocale(locale) {
    currentLocale = localesData.packs?.[locale] ? locale : localesData.defaultLocale;
    currentPack = localesData.packs?.[currentLocale] || currentPack;
    helpData = currentPack.help || { sections: [] };
    changelogData = currentPack.changelog || { entries: [] };
    document.documentElement.lang = currentLocale;
    document.documentElement.dir = currentPack.meta?.direction || 'ltr';
  }

  useLocale(currentLocale);
  titlebar.style.webkitAppRegion = 'drag';
  windowActions.style.webkitAppRegion = 'no-drag';

  const iconTemplate = $('#app-icon-template');
  if (iconTemplate?.content?.firstElementChild) {
    for (const container of [$('.title-icon'), $('.brand-logo')]) {
      const svg = iconTemplate.content.firstElementChild.cloneNode(true);
      svg.removeAttribute('width');
      svg.removeAttribute('height');
      Object.assign(svg.style, { width: '100%', height: '100%', display: 'block' });
      container.replaceChildren(svg);
      container.style.background = 'transparent';
      container.style.boxShadow = 'none';
    }
  }

  const extraStyle = document.createElement('style');
  extraStyle.textContent = `
    .titlebar{position:relative;z-index:1100}
    .global-disabled-overlay{position:absolute;z-index:900;left:0;right:0;top:42px;bottom:0;display:none;align-items:center;justify-content:center;padding:36px;background:rgba(0,0,0,.70);-webkit-app-region:no-drag}.global-disabled-overlay.show{display:flex}.global-disabled-message{max-width:620px;color:#FFF;font-size:17px;font-weight:650;line-height:1.7;text-align:center;white-space:pre-line;text-shadow:0 1px 3px rgba(0,0,0,.35)}
    body.app-booting .app{visibility:hidden}.language-screen{position:absolute;z-index:900;left:0;right:0;top:42px;bottom:0;display:none;padding:28px 34px;background:#FFF;overflow-y:auto;-webkit-app-region:no-drag}.language-grid{display:grid;grid-template-columns:repeat(5,minmax(0,1fr));gap:20px 24px}.language-choice{height:50px;padding:0 10px;border:1px solid #DDE4ED;border-radius:9px;background:#FFF;color:#34445B;font-size:13px;cursor:pointer}.language-choice:hover{border-color:#8DBDFF;background:#F5F9FF;color:#1769E8}.language-choice:active{transform:translateY(1px)}body.language-selection .language-screen{display:block}body.language-selection .title-text,body.language-selection .global-input-control,body.language-selection .win-btn.topmost,body.language-selection .win-btn.text-action{display:none!important}
    .settings-backdrop,.about-backdrop,.help-backdrop{position:fixed;inset:0;z-index:1200;display:none;align-items:center;justify-content:center;background:rgba(25,36,55,.28);backdrop-filter:blur(2px);-webkit-app-region:no-drag}.settings-backdrop.show,.about-backdrop.show,.help-backdrop.show{display:flex}
    .settings-dialog{display:flex;flex-direction:column;width:780px;max-height:520px;padding:22px;border:1px solid #E1E7F0;border-radius:17px;background:#FFF;box-shadow:0 20px 55px rgba(31,45,70,.22);color:#1F2D43}.settings-head,.about-head,.help-head{display:flex;align-items:center;justify-content:space-between;margin-bottom:17px}.settings-title,.about-title,.help-title{font-size:18px;font-weight:700}.settings-close,.about-close,.help-close{width:30px;height:30px;border:0;border-radius:8px;background:transparent;color:#6E7B8D;font-size:21px;cursor:pointer}.settings-close:hover,.about-close:hover,.help-close:hover{background:#F0F3F7;color:#27364C}
    .settings-list{min-height:0;display:grid;gap:9px;overflow-y:auto;padding-right:4px}.settings-row{display:flex;align-items:center;justify-content:space-between;min-height:62px;padding:0 15px;border:1px solid #E5EAF2;border-radius:12px;background:#FAFBFD}.settings-copy{min-width:0}.settings-name{margin-bottom:4px;font-size:14px;font-weight:650;color:#24334A}.settings-desc{color:#8792A3;font-size:11.5px;line-height:1.4;white-space:nowrap}.language-select{flex:0 0 auto;width:150px;height:32px;margin-left:18px;padding:0 8px;border:1px solid #DCE3EC;border-radius:7px;background:#FFF;color:#526076;font-size:11.5px;outline:none}.settings-switch{position:relative;flex:0 0 auto;width:44px;height:24px;margin-left:18px;padding:0;border:0;border-radius:999px;background:#C8D0DC;cursor:pointer}.settings-switch:after{content:'';position:absolute;left:3px;top:3px;width:18px;height:18px;border-radius:50%;background:#FFF;box-shadow:0 1px 4px rgba(24,37,59,.25);transition:transform .18s}.settings-switch.on{background:#2D73F5}.settings-switch.on:after{transform:translateX(20px)}
    .mapping-item .auto-check-wrap{cursor:pointer}.mapping-item.editing .auto-check-wrap,.mapping-item.unsaved .auto-check-wrap{cursor:default;opacity:.5}.mapping-item.editing .auto-check,.mapping-item.unsaved .auto-check{pointer-events:none}
    .win-btn.text-action{width:auto;min-width:54px;padding:0 10px;display:flex;align-items:center;justify-content:center;color:#59677B;font-size:11px;white-space:nowrap;cursor:pointer}.win-btn.text-action.help{min-width:70px}
    .about-dialog{display:flex;flex-direction:column;width:780px;height:440px;padding:22px;border:1px solid #E1E7F0;border-radius:17px;background:#FFF;box-shadow:0 20px 55px rgba(31,45,70,.22);color:#1F2D43}.about-head{flex:0 0 auto;margin-bottom:14px}.about-body{min-height:0;overflow-y:auto;padding-right:7px;user-select:text}.about-info{display:grid;gap:7px;margin-bottom:14px;padding:13px 15px;border:1px solid #E5EAF2;border-radius:12px;background:#FAFBFD;font-size:13px;color:#43516A}.about-product-line{color:#24334A;font-size:14px;font-weight:700}.about-summary{margin-top:5px;padding-top:10px;border-top:1px solid #E5EAF2;color:#5F6D82;font-size:12.5px;line-height:1.7}.about-summary p{margin:0}.about-section-title{margin:0 0 9px;font-size:14px;font-weight:700;color:#24334A}.version-card{margin-bottom:10px;padding:12px 14px;border:1px solid #DFE6F0;border-radius:12px;background:#FFF}.version-title{margin-bottom:7px;color:#2D73F5;font-size:13px;font-weight:700}.version-card ul{margin:0;padding-left:18px;color:#5F6D82;font-size:12px;line-height:1.65}.about-link{width:max-content;padding:0;border:0;background:transparent;color:#1769E8;font:inherit;text-decoration:underline;text-underline-offset:2px;cursor:pointer}.about-link:hover{color:#0F58C7}
    .help-dialog{display:flex;flex-direction:column;width:780px;height:470px;padding:20px;border:1px solid #E1E7F0;border-radius:17px;background:#FFF;box-shadow:0 20px 55px rgba(31,45,70,.22);color:#1F2D43}.help-head{flex:0 0 auto;margin-bottom:13px}.help-layout{min-height:0;flex:1;display:grid;grid-template-columns:205px minmax(0,1fr);border:1px solid #E4E9F0;border-radius:12px;overflow:hidden}.help-nav{min-width:0;min-height:0;overflow-y:auto;padding:9px 8px;background:#F8FAFD;border-right:1px solid #E5EAF1}.help-nav-button{width:100%;min-height:32px;display:flex;align-items:center;gap:7px;padding:5px 9px;border:0;border-radius:7px;background:transparent;color:#536174;font-size:12px;line-height:1.35;text-align:left;cursor:pointer}.help-nav-button:hover{background:#EEF3F9;color:#2D5FAD}.help-nav-button.active{background:#E8F1FF;color:#1769E8;font-weight:400}.help-nav-button.child{padding-left:27px}.help-nav-arrow{width:9px;height:9px;flex:0 0 auto;fill:none;stroke:currentColor;stroke-width:1.8;transition:transform .15s}.help-nav-button.expanded .help-nav-arrow{transform:rotate(90deg)}.help-nav-children{display:none}.help-nav-children.expanded{display:block}.help-content{min-width:0;min-height:0;overflow-y:auto;padding:22px 25px 26px;user-select:text}.help-content h2{margin:0 0 13px;color:#23334A;font-size:19px}.help-content h3{margin:18px 0 8px;color:#34445B;font-size:13px}.help-content p,.help-content li{color:#5C6A7E;font-size:12.5px;line-height:1.75}.help-content p{margin:0 0 10px}.help-content ol,.help-content ul{margin:0;padding-left:21px}.help-content li+li{margin-top:4px}.help-note{margin-top:17px;padding:12px 14px;border:1px solid #DCE9FC;border-radius:9px;background:#F5F9FF}.help-note-title{margin-bottom:5px;color:#2767C7;font-size:12px;font-weight:700}.help-note p{margin:0}
  `;
  document.head.appendChild(extraStyle);

  const languageScreen = document.createElement('div');
  languageScreen.className = 'language-screen';
  languageScreen.innerHTML = '<div class="language-grid"></div>';
  $('.app').appendChild(languageScreen);
  const globalDisabledOverlay = document.createElement('div');
  globalDisabledOverlay.className = 'global-disabled-overlay';
  globalDisabledOverlay.setAttribute('role', 'status');
  globalDisabledOverlay.setAttribute('aria-live', 'polite');
  globalDisabledOverlay.innerHTML = '<div class="global-disabled-message"></div>';
  $('.app').appendChild(globalDisabledOverlay);
  const settingsBackdrop = document.createElement('div');
  settingsBackdrop.className = 'settings-backdrop';
  document.body.appendChild(settingsBackdrop);
  const aboutBackdrop = document.createElement('div');
  aboutBackdrop.className = 'about-backdrop';
  document.body.appendChild(aboutBackdrop);
  const helpBackdrop = document.createElement('div');
  helpBackdrop.className = 'help-backdrop';
  document.body.appendChild(helpBackdrop);

  function createWindowButton(className, title) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = `win-btn ${className} text-action`;
    button.setAttribute('aria-label', title);
    button.innerHTML = `<span>${escapeHtml(title)}</span>`;
    return button;
  }

  const helpButton = createWindowButton('help', t('button.help'));
  const aboutButton = createWindowButton('about', t('button.about'));
  const settingsButton = createWindowButton('settings', t('button.settings'));
  const firstNativeWindowButton = windowActions.firstElementChild;
  for (const button of [helpButton, aboutButton, settingsButton]) windowActions.insertBefore(button, firstNativeWindowButton);

  function renderLanguageSelector() {
    languageScreen.querySelector('.language-grid').innerHTML = (localesData.order || []).filter(locale => localesData.packs?.[locale])
      .map(locale => `<button class="language-choice" type="button" data-language-choice="${escapeHtml(locale)}">${escapeHtml(localesData.packs[locale].meta?.nativeName || locale)}</button>`).join('');
  }

  function renderLocalizedShell() {
    document.title = t('app.windowTitle', { version: APP_VERSION });
    $('.title-text').textContent = document.title;
    $('.app').setAttribute('aria-label', t('app.ariaLabel'));
    windowActions.setAttribute('aria-label', t('window.controls'));
    globalInputSwitch.setAttribute('aria-label', t('window.inputToggle'));
    globalInputDisabledNote.textContent = t('window.inputDisabled');
    globalDisabledOverlay.querySelector('.global-disabled-message').textContent = t('window.inputDisabled');
    topMostButton.setAttribute('aria-label', t('window.topMost'));
    $('.win-btn.minimize').setAttribute('aria-label', t('window.minimize'));
    $('.win-btn.close').setAttribute('aria-label', t('window.close'));
    for (const [button, key] of [[settingsButton, 'button.settings'], [aboutButton, 'button.about'], [helpButton, 'button.help']]) {
      button.setAttribute('aria-label', t(key));
      button.querySelector('span').textContent = t(key);
    }
    const languageOptions = (localesData.order || []).filter(locale => localesData.packs?.[locale])
      .map(locale => `<option value="${escapeHtml(locale)}"${locale === currentLocale ? ' selected' : ''}>${escapeHtml(localesData.packs[locale].meta?.nativeName || locale)}</option>`).join('');
    settingsBackdrop.innerHTML = `<section class="settings-dialog"><div class="settings-head"><div class="settings-title">${escapeHtml(t('settings.title'))}</div><button class="settings-close" type="button">×</button></div><div class="settings-list"><div class="settings-row"><div class="settings-copy"><div class="settings-name">${escapeHtml(t('language.settingName'))}</div><div class="settings-desc">${escapeHtml(t('language.settingDescription'))}</div></div><select id="languageSelect" class="language-select">${languageOptions}</select></div><div class="settings-row"><div class="settings-copy"><div class="settings-name">${escapeHtml(t('settings.autoStart'))}</div><div class="settings-desc">${escapeHtml(t('settings.autoStartDescription'))}</div></div><button class="settings-switch" data-setting="autoStart" type="button"></button></div><div class="settings-row"><div class="settings-copy"><div class="settings-name">${escapeHtml(t('settings.trayIcon'))}</div><div class="settings-desc">${escapeHtml(t('settings.trayIconDescription'))}</div></div><button class="settings-switch" data-setting="trayIcon" type="button"></button></div></div></section>`;
    aboutBackdrop.innerHTML = `<section class="about-dialog"><div class="about-head"><div class="about-title">${escapeHtml(t('about.title'))}</div><button class="about-close" type="button">×</button></div><div class="about-body"><div class="about-info"><div class="about-product-line">${escapeHtml(t('about.productLine', { version: APP_VERSION }))}</div><button class="about-link" data-open-author-site type="button">${AUTHOR_URL}</button><button class="about-link" data-open-repository-site type="button">${REPOSITORY_URL}</button><div class="about-summary">${currentPack.aboutHtml || ''}</div></div><div class="about-section-title">${escapeHtml(t('about.changelog'))}</div><div class="changelog-list"></div></div></section>`;
    helpBackdrop.innerHTML = `<section class="help-dialog"><div class="help-head"><div class="help-title">${escapeHtml(t('help.title'))}</div><button class="help-close" type="button">×</button></div><div class="help-layout"><nav class="help-nav" aria-label="${escapeHtml(t('help.navigation'))}"></nav><article class="help-content"></article></div></section>`;
    $('.brand-title').textContent = t('mode.mapping');
    $('.brand-subtitle').textContent = t('brand.subtitle');
    panelTitle.innerHTML = `<span class="panel-title-dot"></span>${escapeHtml(t('panel.mapping'))}`;
    $('.panel').setAttribute('aria-label', t('panel.mapping'));
    addMapping.textContent = t('mapping.add');
    addWarning.textContent = t('mapping.pendingWarning');
    $('#confirmCancel').textContent = t('button.cancel');
    $('#confirmDelete').textContent = t('button.delete');
    renderChangelog();
    renderSettings();
  }

  function compareVersionsDescending(first, second) {
    const left = String(first.version || '').split('.').map(Number);
    const right = String(second.version || '').split('.').map(Number);
    for (let index = 0; index < Math.max(left.length, right.length); index += 1) {
      const difference = (right[index] || 0) - (left[index] || 0);
      if (difference) return difference;
    }
    return 0;
  }

  function renderChangelog() {
    const container = aboutBackdrop.querySelector('.changelog-list');
    if (!container) return;
    const entries = Array.isArray(changelogData.entries) ? [...changelogData.entries].sort(compareVersionsDescending) : [];
    container.innerHTML = entries.length ? entries.map(entry => `<div class="version-card"><div class="version-title">${escapeHtml(t('about.versionHeading', { version: entry.version }))}</div><ul>${(entry.items || []).map(item => `<li>${escapeHtml(item)}</li>`).join('')}</ul></div>`).join('') : `<div class="version-card"><div class="version-title">${escapeHtml(t('about.changelogLoadFailed'))}</div></div>`;
  }

  function findHelpPath(nodes, targetId, path = []) {
    for (const node of nodes || []) {
      const nextPath = [...path, node];
      if (node.id === targetId) return nextPath;
      const found = findHelpPath(node.children, targetId, nextPath);
      if (found) return found;
    }
    return null;
  }

  function firstHelpLeaf(nodes) {
    for (const node of nodes || []) {
      if (Array.isArray(node.children) && node.children.length) {
        const leaf = firstHelpLeaf(node.children);
        if (leaf) return leaf;
      } else if (node.id) return node;
    }
    return null;
  }

  function renderHelpNavigation() {
    const renderNodes = items => (items || []).map(node => {
      const hasChildren = Array.isArray(node.children) && node.children.length;
      if (!hasChildren) return `<button class="help-nav-button child${activeHelpId === node.id ? ' active' : ''}" data-help-leaf="${escapeHtml(node.id)}" type="button">${escapeHtml(node.title)}</button>`;
      const expanded = expandedHelpNodes.has(node.id);
      return `<div class="help-nav-node"><button class="help-nav-button${expanded ? ' expanded' : ''}" data-help-parent="${escapeHtml(node.id)}" type="button"><svg class="help-nav-arrow" viewBox="0 0 10 10"><path d="M3 1.8 6.4 5 3 8.2"/></svg><span>${escapeHtml(node.title)}</span></button><div class="help-nav-children${expanded ? ' expanded' : ''}">${renderNodes(node.children)}</div></div>`;
    }).join('');
    helpBackdrop.querySelector('.help-nav').innerHTML = renderNodes(helpData.sections);
    lockKeyboardFocus(helpBackdrop);
  }

  function renderHelpContent(id) {
    const path = findHelpPath(helpData.sections, id);
    const leaf = path?.[path.length - 1] || firstHelpLeaf(helpData.sections);
    const content = helpBackdrop.querySelector('.help-content');
    if (!leaf) {
      activeHelpId = '';
      content.innerHTML = `<h2>${escapeHtml(t('help.loadFailedTitle'))}</h2><p>${escapeHtml(t('help.loadFailedText'))}</p>`;
      return;
    }
    activeHelpId = leaf.id;
    for (const parent of path?.slice(0, -1) || []) expandedHelpNodes.add(parent.id);
    const body = String(leaf.html || '').replaceAll('<div class="help-note-title"></div>', `<div class="help-note-title">${escapeHtml(t('help.note'))}</div>`);
    content.innerHTML = `<h2>${escapeHtml(leaf.title)}</h2>${body || `<p>${escapeHtml(t('help.empty'))}</p>`}`;
    content.scrollTop = 0;
    renderHelpNavigation();
  }

  function openHelp() {
    const desired = findHelpPath(helpData.sections, 'mapping-basic') ? 'mapping-basic' : firstHelpLeaf(helpData.sections)?.id;
    renderHelpContent(desired);
    helpBackdrop.classList.add('show');
  }

  async function callAhk(name, ...args) { return await ahk.global[name](...args); }
  function parseResult(raw) { return typeof raw === 'string' ? JSON.parse(raw) : raw; }

  function showStatus(message) {
    if (statusTimer) clearTimeout(statusTimer);
    addWarning.textContent = String(message || t('mapping.pendingWarning'));
    addWarning.classList.add('show');
    statusTimer = setTimeout(() => { addWarning.classList.remove('show'); statusTimer = null; }, 3000);
  }

  function hideStatus() {
    if (statusTimer) clearTimeout(statusTimer);
    statusTimer = null;
    addWarning.classList.remove('show');
  }

  function askConfirm(title, text, confirmLabel = t('button.confirm')) {
    if (pendingConfirm) pendingConfirm(false);
    confirmTitle.textContent = title;
    confirmText.textContent = text;
    $('#confirmCancel').hidden = false;
    $('#confirmDelete').classList.add('danger');
    $('#confirmDelete').textContent = confirmLabel;
    confirmBackdrop.classList.add('show');
    return new Promise(resolve => { pendingConfirm = resolve; });
  }

  function showNotice(title, text, confirmLabel = t('button.gotIt')) {
    if (pendingConfirm) pendingConfirm(false);
    confirmTitle.textContent = title;
    confirmText.textContent = text;
    $('#confirmCancel').hidden = true;
    $('#confirmDelete').classList.remove('danger');
    $('#confirmDelete').textContent = confirmLabel;
    confirmBackdrop.classList.add('show');
    return new Promise(resolve => { pendingConfirm = resolve; });
  }

  function resolveConfirm(value) {
    confirmBackdrop.classList.remove('show');
    const resolve = pendingConfirm;
    pendingConfirm = null;
    $('#confirmCancel').hidden = false;
    if (resolve) resolve(value);
  }

  function lockKeyboardFocus(root = document) {
    root.querySelectorAll('button,[role="button"]').forEach(element => element.setAttribute('tabindex', '-1'));
  }

  function applyState(nextState) {
    if (nextState.locale && nextState.locale !== currentLocale) {
      useLocale(nextState.locale);
      renderLocalizedShell();
    }
    state = nextState;
    mappings = (state.mappings || []).map(item => ({ id: Number(item.id), from: item.fromLabel, fromKey: item.from, to: item.to === 'NONE' ? '' : item.toLabel, toKey: item.to, enabled: Boolean(item.enabled), global: Boolean(item.global), saved: true, editing: false }));
    nextMappingId = mappings.reduce((maximum, item) => Math.max(maximum, item.id), 0) + 1;
    renderGlobalInputSwitch();
    renderTopMost();
    renderSettings();
    renderMappings();
    document.body.classList.toggle('language-selection', !state.languageSelected);
  }

  async function refreshState() { applyState(parseResult(await callAhk('GetInitialState'))); }

  function renderGlobalInputSwitch() {
    const enabled = state.inputEnabled !== false;
    globalInputSwitch.classList.toggle('on', enabled);
    globalInputSwitch.setAttribute('aria-checked', enabled ? 'true' : 'false');
    globalInputDisabledNote.classList.toggle('show', !enabled);
    globalDisabledOverlay.classList.toggle('show', !enabled);
    globalDisabledOverlay.setAttribute('aria-hidden', enabled ? 'true' : 'false');
  }

  function renderTopMost() {
    const enabled = Boolean(state.topMost);
    topMostButton.classList.toggle('active', enabled);
    topMostButton.setAttribute('aria-pressed', enabled ? 'true' : 'false');
  }

  function renderSettings() {
    settingsBackdrop.querySelectorAll('[data-setting]').forEach(button => {
      const enabled = Boolean(state.settings?.[button.dataset.setting]);
      button.classList.toggle('on', enabled);
      button.setAttribute('aria-pressed', enabled ? 'true' : 'false');
    });
  }

  function renderRowSelection(item, disabled = false) {
    return `<span class="auto-check-wrap" ${disabled ? '' : `data-mapping-toggle="${item.id}"`}><input class="auto-check" type="checkbox" ${item.enabled ? 'checked' : ''} ${disabled ? 'disabled' : ''}></span>`;
  }

  function renderMappings() {
    const saved = mappings.filter(item => item.saved).length;
    const pending = mappings.filter(item => !item.saved).length;
    countEl.textContent = t(pending ? 'mapping.countPending' : 'mapping.count', { saved, pending });
    if (!mappings.length) {
      mappingList.innerHTML = `<div class="empty-state">${escapeHtml(t('mapping.empty'))}</div>`;
      return;
    }
    mappingList.innerHTML = mappings.map(item => {
      if (!item.saved || item.editing) {
        return `<div class="mapping-item ${item.saved ? 'editing' : 'unsaved'}" data-id="${item.id}"><span class="status-tag">${escapeHtml(t(item.saved ? 'mapping.editing' : 'mapping.unsaved'))}</span>${renderRowSelection(item, true)}<div class="map-flow"><span class="record-wrap"><button class="record-box${recording?.id === item.id && recording.field === 'from' ? ' recording' : ''}" data-action="record" data-field="from" type="button" aria-label="${escapeHtml(t('mapping.recordSource'))}">${escapeHtml(item.from)}</button><button class="record-clear" data-clear-record="mapping" data-field="from" type="button" aria-label="${escapeHtml(t('button.clearRecordedKey'))}">×</button></span><span class="arrow">→</span><span class="record-wrap"><button class="record-box${recording?.id === item.id && recording.field === 'to' ? ' recording' : ''}" data-action="record" data-field="to" type="button" aria-label="${escapeHtml(t('mapping.recordTarget'))}">${escapeHtml(item.to || t('mapping.none'))}</button><button class="record-clear" data-clear-record="mapping" data-field="to" type="button" aria-label="${escapeHtml(t('button.clearRecordedKey'))}">×</button></span></div><div class="item-actions"><button class="mini-btn primary" data-action="save" type="button" ${!item.from ? 'disabled' : ''}>${escapeHtml(t('button.save'))}</button><button class="mini-btn ${item.saved ? '' : 'danger'}" data-action="${item.saved ? 'cancel-edit' : 'delete'}" type="button">${escapeHtml(t(item.saved ? 'button.cancel' : 'button.delete'))}</button></div></div>`;
      }
      return `<div class="mapping-item" data-id="${item.id}">${renderRowSelection(item)}<div class="map-flow"><span class="record-box saved-value">${escapeHtml(item.from)}</span><span class="arrow">→</span><span class="record-box saved-value">${escapeHtml(item.to || t('mapping.none'))}</span></div><div class="item-actions"><button class="mini-btn" data-action="edit" type="button">${escapeHtml(t('button.edit'))}</button><button class="mini-btn danger" data-action="delete" type="button">${escapeHtml(t('button.delete'))}</button></div></div>`;
    }).join('');
    lockKeyboardFocus(mappingList);
  }

  async function beginMappingCapture(item, field) {
    recording = { type: 'mapping', id: item.id, field };
    mappingPointerInside = true;
    renderMappings();
    await callAhk('BeginCapture', item.id, field, true);
  }

  function isActiveMappingRecordTarget(target) {
    if (recording?.type !== 'mapping' || !(target instanceof Element)) return false;
    const box = target.closest('button.record-box[data-action="record"]');
    const row = box?.closest('.mapping-item');
    return Boolean(box && row && Number(row.dataset.id) === Number(recording.id) && box.dataset.field === recording.field);
  }

  function updateMappingPointerInside(target) {
    if (recording?.type !== 'mapping') { mappingPointerInside = false; return; }
    const inside = isActiveMappingRecordTarget(target);
    if (inside === mappingPointerInside) return;
    mappingPointerInside = inside;
    callAhk('SetMappingCapturePointerInside', inside).catch(error => showStatus(error.message || String(error)));
  }

  async function cancelMappingCaptureFromUi(render = true) {
    if (recording?.type !== 'mapping') return;
    await callAhk('CancelCapture');
    recording = null;
    mappingPointerInside = false;
    if (render) renderMappings();
  }

  async function clearRecordedField(button) {
    const row = button.closest('.mapping-item');
    const item = mappings.find(entry => entry.id === Number(row?.dataset.id));
    const field = button.dataset.field;
    if (!item || !['from', 'to'].includes(field)) return;
    await callAhk('CancelCapture');
    recording = null;
    mappingPointerInside = false;
    if (field === 'from') { item.from = ''; item.fromKey = ''; }
    else { item.to = ''; item.toKey = 'NONE'; }
    renderMappings();
  }

  async function saveMappingItem(item) {
    const result = parseResult(await callAhk('SaveMapping', item.id, item.fromKey, item.toKey || 'NONE'));
    if (!result.ok) return showStatus(result.message);
    recording = null;
    hideStatus();
    await refreshState();
  }

  async function changeLanguage(locale) {
    if (!localesData.packs?.[locale]) return;
    await callAhk('CancelCapture');
    recording = null;
    mappingPointerInside = false;
    const result = parseResult(await callAhk('SetLanguage', locale));
    if (!result.ok) return showStatus(result.message);
    useLocale(locale);
    renderLocalizedShell();
    applyState(result.state);
    if (!result.saved) await showNotice(t('settings.title'), result.message || t('message.languageSaveFailed'));
  }

  document.addEventListener('change', event => {
    if (event.target.matches('#languageSelect')) changeLanguage(event.target.value).catch(error => showStatus(error.message || String(error)));
  });

  document.addEventListener('click', async event => {
    try {
      const target = event.target;
      const languageChoice = target.closest('[data-language-choice]');
      if (languageChoice) { await changeLanguage(languageChoice.dataset.languageChoice); return; }
      const clearRecorded = target.closest('[data-clear-record="mapping"]');
      if (clearRecorded) { await clearRecordedField(clearRecorded); return; }
      if (recording?.type === 'mapping' && !isActiveMappingRecordTarget(target)) await cancelMappingCaptureFromUi();
      if (target.closest('#globalInputSwitch')) {
        const result = parseResult(await callAhk('SetInputEnabled', state.inputEnabled === false));
        if (!result.ok) return showStatus(result.message);
        state.inputEnabled = Boolean(result.enabled);
        recording = null;
        renderGlobalInputSwitch();
        renderMappings();
        return;
      }
      if (target.closest('.win-btn.close')) { await callAhk('CloseApp'); return; }
      if (target.closest('.win-btn.minimize')) { await callAhk('MinimizeApp'); return; }
      if (target.closest('.win-btn.topmost')) {
        const result = parseResult(await callAhk('SetWindowTopMost', !state.topMost));
        if (!result.ok) return showStatus(result.message);
        state.topMost = Boolean(result.enabled);
        renderTopMost();
        return;
      }
      if (target.closest('.win-btn.settings')) { renderSettings(); settingsBackdrop.classList.add('show'); return; }
      if (target.closest('.settings-close')) { settingsBackdrop.classList.remove('show'); return; }
      if (target.closest('.win-btn.about')) { renderChangelog(); aboutBackdrop.classList.add('show'); return; }
      if (target.closest('.about-close')) { aboutBackdrop.classList.remove('show'); return; }
      if (target.closest('.win-btn.help')) { openHelp(); return; }
      if (target.closest('.help-close')) { helpBackdrop.classList.remove('show'); return; }
      if (target.closest('[data-open-author-site]')) {
        const result = parseResult(await callAhk('OpenAuthorWebsite'));
        if (!result.ok) await showNotice(t('about.title'), result.message || t('message.openWebsiteFailed'));
        return;
      }
      if (target.closest('[data-open-repository-site]')) {
        const result = parseResult(await callAhk('OpenRepositoryWebsite'));
        if (!result.ok) await showNotice(t('about.title'), result.message || t('message.openRepositoryFailed'));
        return;
      }
      const helpParent = target.closest('[data-help-parent]');
      if (helpParent) {
        const id = helpParent.dataset.helpParent;
        if (expandedHelpNodes.has(id)) expandedHelpNodes.delete(id); else expandedHelpNodes.add(id);
        renderHelpNavigation();
        return;
      }
      const helpLeaf = target.closest('[data-help-leaf]');
      if (helpLeaf) { renderHelpContent(helpLeaf.dataset.helpLeaf); return; }
      if (target.closest('#confirmCancel')) { resolveConfirm(false); return; }
      if (target.closest('#confirmDelete')) { resolveConfirm(true); return; }
      const settingButton = target.closest('[data-setting]');
      if (settingButton) {
        const key = settingButton.dataset.setting;
        const method = key === 'autoStart' ? 'SetAutoStart' : 'SetTrayIcon';
        const result = parseResult(await callAhk(method, !state.settings[key]));
        if (!result.ok) showStatus(result.message);
        state.settings[key] = Boolean(result.value);
        renderSettings();
        return;
      }
      if (target.closest('#addMapping')) {
        if (mappings.some(item => !item.saved)) return showStatus(t('mapping.pendingWarning'));
        mappings.unshift({ id: nextMappingId++, from: '', fromKey: '', to: '', toKey: 'NONE', enabled: false, global: false, saved: false, editing: false });
        hideStatus();
        renderMappings();
        return;
      }
      const mappingToggle = target.closest('[data-mapping-toggle]');
      if (mappingToggle) {
        const item = mappings.find(row => row.id === Number(mappingToggle.dataset.mappingToggle));
        if (!item) return;
        const result = parseResult(await callAhk('SetMappingEnabled', item.id, !item.enabled));
        if (!result.ok) return showStatus(result.message);
        await refreshState();
        return;
      }
      const mappingButton = target.closest('button[data-action]');
      if (!mappingButton) return;
      const item = mappings.find(row => row.id === Number(mappingButton.closest('.mapping-item')?.dataset.id));
      if (!item) return;
      const action = mappingButton.dataset.action;
      if (action === 'record') return beginMappingCapture(item, mappingButton.dataset.field);
      if (action === 'save') return saveMappingItem(item);
      if (action === 'edit') {
        item.editing = true;
        item.beforeEdit = { from: item.from, fromKey: item.fromKey, to: item.to, toKey: item.toKey };
        renderMappings();
        return;
      }
      if (action === 'cancel-edit') {
        Object.assign(item, item.beforeEdit);
        item.editing = false;
        delete item.beforeEdit;
        recording = null;
        mappingPointerInside = false;
        await callAhk('CancelCapture');
        renderMappings();
        return;
      }
      if (action === 'delete') {
        const confirmed = !item.saved || await askConfirm(t('mapping.deleteTitle'), t('mapping.deleteText', { mapping: `${item.from} → ${item.to || t('mapping.none')}` }), t('button.delete'));
        if (!confirmed) return;
        recording = null;
        mappingPointerInside = false;
        await callAhk('CancelCapture');
        if (item.saved) {
          const result = parseResult(await callAhk('DeleteMapping', item.id));
          if (!result.ok) return showStatus(result.message);
        }
        mappings = mappings.filter(row => row.id !== item.id);
        renderMappings();
      }
    } catch (error) {
      showStatus(error.message || String(error));
    }
  }, true);

  document.addEventListener('pointermove', event => updateMappingPointerInside(event.target), true);
  document.addEventListener('pointerleave', () => updateMappingPointerInside(null), true);

  function isAllowedKeyboard(event) {
    if (event.key === 'Alt' || event.altKey) return true;
    if (event.ctrlKey && !event.altKey && !event.metaKey && String(event.key).toLowerCase() === 'c') return true;
    return event.key === 'Control';
  }

  for (const eventName of ['keydown', 'keypress', 'keyup']) {
    document.addEventListener(eventName, event => {
      if (!isAllowedKeyboard(event)) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
  }
  document.addEventListener('contextmenu', event => { event.preventDefault(); event.stopImmediatePropagation(); }, true);
  for (const eventName of ['mousedown', 'mouseup', 'auxclick', 'pointerdown', 'pointerup']) {
    document.addEventListener(eventName, event => {
      if (event.button !== 0) { event.preventDefault(); event.stopImmediatePropagation(); }
    }, true);
  }
  document.addEventListener('wheel', event => {
    if (event.ctrlKey || event.altKey || event.metaKey) { event.preventDefault(); event.stopImmediatePropagation(); }
  }, { capture: true, passive: false });

  window.app = {
    receiveCaptureProgress(id, field, keyName, label) {
      const item = mappings.find(row => row.id === Number(id));
      if (!item) return;
      item[field] = label;
      item[`${field}Key`] = keyName;
      renderMappings();
    },
    receiveCapture(id, field, keyName, label) {
      const item = mappings.find(row => row.id === Number(id));
      if (!item) return;
      item[field] = label;
      item[`${field}Key`] = keyName;
      recording = null;
      mappingPointerInside = false;
      renderMappings();
    },
    captureCancelled() { recording = null; mappingPointerInside = false; renderMappings(); },
    captureWarning(message) { showStatus(message); },
    backendError(message) { recording = null; showStatus(message); }
  };

  renderLanguageSelector();
  document.body.classList.toggle('language-selection', !bootstrap.languageSelected);
  renderLocalizedShell();
  lockKeyboardFocus();
  refreshState().catch(error => showStatus(error.message || String(error))).finally(() => document.body.classList.remove('app-booting'));
})();
