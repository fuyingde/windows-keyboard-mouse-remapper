(() => {
  const mappingList = document.getElementById('mappingList');
  const addWarning = document.getElementById('addWarning');
  const countEl = document.getElementById('count');
  const confirmBackdrop = document.getElementById('confirmBackdrop');
  const confirmText = document.getElementById('confirmText');
  const settingsBackdrop = document.getElementById('settingsBackdrop');
  const aboutBackdrop = document.getElementById('aboutBackdrop');
  const settingsButton = document.querySelector('.win-btn.settings');
  const aboutButton = document.querySelector('.win-btn.about');
  const titleText = document.getElementById('titleText');
  const aboutVersion = document.getElementById('aboutVersion');
  const defaultStatusMessage = addWarning.textContent.trim();

  let nextId = 1;
  let mappings = [];
  let recording = null;
  let mappingPointerInside = false;
  let pendingDeleteId = null;
  let settingsState = { autoStart: false, trayIcon: true };
  let statusTimer = 0;

  const icons = {
    edit: '<svg viewBox="0 0 16 16"><path d="M10.9 2.7l2.4 2.4M3.1 12.9l2.8-.6 7.1-7.1a1.7 1.7 0 0 0-2.4-2.4L3.5 9.9l-.4 3z"/></svg>',
    trash: '<svg viewBox="0 0 16 16"><path d="M3 4.7h10M6 2.7h4M5 6.5v5.7M8 6.5v5.7M11 6.5v5.7M4.1 4.7l.6 8.2h6.6l.6-8.2"/></svg>'
  };

  const titlebar = document.querySelector('.titlebar');
  const windowActions = document.querySelector('.window-actions');
  document.documentElement.style.minWidth = '960px';
  document.documentElement.style.minHeight = '550px';
  document.documentElement.style.overflow = 'hidden';
  document.body.style.minWidth = '960px';
  document.body.style.minHeight = '550px';
  document.body.style.overflow = 'hidden';
  titlebar.style.webkitAppRegion = 'drag';
  windowActions.style.webkitAppRegion = 'no-drag';

  // 侧键进入 WebView2 会把界面点空白（v1.6）。右键/中键也不放进页面。
  // 键盘不再拦截，这样窗口在前台时 Alt+Tab、Win 等系统快捷键仍然可用。
  document.addEventListener('contextmenu', event => {
    event.preventDefault();
    event.stopImmediatePropagation();
  }, true);

  for (const eventName of ['mousedown', 'mouseup', 'auxclick', 'pointerdown', 'pointerup']) {
    document.addEventListener(eventName, event => {
      if (event.button !== 0) {
        event.preventDefault();
        event.stopImmediatePropagation();
      }
    }, true);
  }

  function escapeHtml(value) {
    return String(value ?? '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  function applyVersion(version) {
    document.title = '键鼠映射';
    if (titleText) titleText.textContent = '键鼠映射';
    if (aboutVersion) aboutVersion.textContent = `v${version}`;
  }

  function showStatus(message = defaultStatusMessage) {
    if (statusTimer) clearTimeout(statusTimer);
    addWarning.textContent = String(message || defaultStatusMessage);
    addWarning.classList.add('show');
    statusTimer = setTimeout(() => {
      addWarning.classList.remove('show');
      statusTimer = 0;
    }, 3000);
  }

  function hideStatus() {
    if (statusTimer) clearTimeout(statusTimer);
    statusTimer = 0;
    addWarning.textContent = defaultStatusMessage;
    addWarning.classList.remove('show');
  }

  function renderSettings() {
    settingsBackdrop.querySelectorAll('.settings-switch').forEach(button => {
      const enabled = Boolean(settingsState[button.dataset.setting]);
      button.classList.toggle('on', enabled);
      button.setAttribute('aria-checked', enabled ? 'true' : 'false');
      button.title = enabled ? '已开启' : '已关闭';
    });
  }

  function openSettings() {
    aboutBackdrop.classList.remove('show');
    aboutBackdrop.setAttribute('aria-hidden', 'true');
    renderSettings();
    settingsBackdrop.classList.add('show');
    settingsBackdrop.setAttribute('aria-hidden', 'false');
    document.getElementById('settingsClose').focus();
  }

  function closeSettings() {
    settingsBackdrop.classList.remove('show');
    settingsBackdrop.setAttribute('aria-hidden', 'true');
    settingsButton.focus();
  }

  function openAbout() {
    settingsBackdrop.classList.remove('show');
    settingsBackdrop.setAttribute('aria-hidden', 'true');
    aboutBackdrop.classList.add('show');
    aboutBackdrop.setAttribute('aria-hidden', 'false');
    document.getElementById('aboutClose').focus();
  }

  function closeAbout() {
    aboutBackdrop.classList.remove('show');
    aboutBackdrop.setAttribute('aria-hidden', 'true');
    aboutButton.focus();
  }

  async function changeSetting(button) {
    const setting = button.dataset.setting;
    const nextValue = !Boolean(settingsState[setting]);
    button.disabled = true;
    try {
      const backendMethod = setting === 'autoStart' ? 'SetAutoStart' : 'SetTrayIcon';
      const result = parseResult(await callAhk(backendMethod, nextValue));
      settingsState[setting] = Boolean(result.value);
      renderSettings();
      if (!result.ok) showStatus(result.message || '设置保存失败。');
      else hideStatus();
    } finally {
      button.disabled = false;
    }
  }

  function openDeleteConfirm(item) {
    pendingDeleteId = item.id;
    confirmText.textContent = `确定删除“${item.from} → ${item.to || '无'}”这条映射吗？删除后无法恢复。`;
    confirmBackdrop.classList.add('show');
    confirmBackdrop.setAttribute('aria-hidden', 'false');
    document.getElementById('confirmDelete').focus();
  }

  function closeDeleteConfirm() {
    pendingDeleteId = null;
    confirmBackdrop.classList.remove('show');
    confirmBackdrop.setAttribute('aria-hidden', 'true');
  }

  function updateCount() {
    const saved = mappings.filter(m => m.saved).length;
    const pending = mappings.filter(m => !m.saved).length;
    countEl.textContent = pending ? `${saved} 条已保存 · ${pending} 条待保存` : `${saved} 条映射`;
  }

  function recordClass(item, field) {
    return recording?.id === item.id && recording.field === field ? ' recording' : '';
  }

  function render() {
    updateCount();

    if (!mappings.length) {
      mappingList.innerHTML = '<div class="empty-state">暂无映射，点击左侧“添加映射”开始。</div>';
      return;
    }

    mappingList.innerHTML = mappings.map(item => {
      const fromLabel = escapeHtml(item.from || '');
      const toLabel = escapeHtml(item.to || '无');

      if (!item.saved) {
        return `
          <div class="mapping-item unsaved" data-id="${item.id}">
            <span class="status-tag">未保存</span>
            <div class="map-flow">
              <button type="button" class="record-box${recordClass(item, 'from')}" data-action="record" data-field="from" aria-label="设置触发按键">${fromLabel}</button>
              <span class="arrow">→</span>
              <span class="record-wrap">
                <button type="button" class="record-box${recordClass(item, 'to')}" data-action="record" data-field="to" aria-label="设置映射按键">${toLabel}</button>
                <button type="button" class="clear-target" data-action="clear-target" aria-label="清空映射">×</button>
              </span>
            </div>
            <div class="item-actions">
              <button type="button" class="mini-btn primary" data-action="save" ${!item.from ? 'disabled' : ''}>保存</button>
              <button type="button" class="mini-btn danger" data-action="delete">删除</button>
            </div>
          </div>`;
      }

      if (item.editing) {
        return `
          <div class="mapping-item editing" data-id="${item.id}">
            <span class="status-tag">修改中</span>
            <div class="map-flow">
              <button type="button" class="record-box${recordClass(item, 'from')}" data-action="record" data-field="from" aria-label="设置触发按键">${fromLabel}</button>
              <span class="arrow">→</span>
              <span class="record-wrap">
                <button type="button" class="record-box${recordClass(item, 'to')}" data-action="record" data-field="to" aria-label="设置映射按键">${toLabel}</button>
                <button type="button" class="clear-target" data-action="clear-target" aria-label="清空映射">×</button>
              </span>
            </div>
            <div class="item-actions">
              <button type="button" class="mini-btn primary" data-action="save-edit" ${!item.from ? 'disabled' : ''}>保存</button>
              <button type="button" class="mini-btn" data-action="cancel-edit">取消</button>
            </div>
          </div>`;
      }

      return `
          <div class="mapping-item" data-id="${item.id}">
            <div class="map-flow">
            <span class="record-box saved-value">${fromLabel}</span>
            <span class="arrow">→</span>
            <span class="record-box saved-value">${toLabel}</span>
          </div>
          <div class="item-actions">
            <button type="button" class="mini-btn" data-action="edit">${icons.edit} 修改</button>
            <button type="button" class="mini-btn danger" data-action="delete">${icons.trash} 删除</button>
          </div>
        </div>`;
    }).join('');
  }

  async function callAhk(name, ...args) {
    return await ahk.global[name](...args);
  }

  function parseResult(raw) {
    return typeof raw === 'string' ? JSON.parse(raw) : raw;
  }

  async function beginCapture(item, field) {
    recording = { id: item.id, field };
    mappingPointerInside = true;
    render();
    await callAhk('BeginCapture', item.id, field, true);
  }

  function isActiveMappingRecordTarget(target) {
    if (!recording || !(target instanceof Element)) return false;
    const box = target.closest('button.record-box[data-action="record"]');
    const row = box?.closest('.mapping-item');
    return Boolean(box && row
      && Number(row.dataset.id) === Number(recording.id)
      && box.dataset.field === recording.field);
  }

  function updateMappingPointerInside(target) {
    if (!recording) {
      mappingPointerInside = false;
      return;
    }
    const inside = isActiveMappingRecordTarget(target);
    if (inside === mappingPointerInside) return;
    mappingPointerInside = inside;
    callAhk('SetMappingCapturePointerInside', inside).catch(error => showStatus(error.message || String(error)));
  }

  async function cancelMappingCaptureFromUi(shouldRender = true) {
    if (!recording) return;
    await callAhk('CancelCapture');
    recording = null;
    mappingPointerInside = false;
    if (shouldRender) render();
  }

  async function saveItem(item) {
    if (!item.from) return;
    const result = parseResult(await callAhk('SaveMapping', item.id, item.fromKey, item.toKey || 'NONE'));
    if (!result.ok) {
      showStatus(result.message || '保存失败。');
      return;
    }

    item.saved = true;
    item.editing = false;
    delete item.beforeEdit;
    recording = null;
    hideStatus();
    render();
  }

  async function handleClick(event) {
    if (recording && !isActiveMappingRecordTarget(event.target))
      await cancelMappingCaptureFromUi();

    const winButton = event.target.closest('.win-btn');
    if (winButton) {
      event.preventDefault();
      event.stopImmediatePropagation();
      if (winButton.classList.contains('about')) {
        await cancelMappingCaptureFromUi(false);
        openAbout();
      } else if (winButton.classList.contains('settings')) {
        await cancelMappingCaptureFromUi(false);
        openSettings();
      } else if (winButton.classList.contains('close'))
        await callAhk('CloseApp');
      else
        await callAhk('MinimizeApp');
      return;
    }

    if (event.target.closest('#aboutClose') || event.target === aboutBackdrop) {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeAbout();
      return;
    }

    if (event.target.closest('#settingsClose') || event.target === settingsBackdrop) {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeSettings();
      return;
    }

    const settingButton = event.target.closest('.settings-switch[data-setting]');
    if (settingButton) {
      event.preventDefault();
      event.stopImmediatePropagation();
      await changeSetting(settingButton);
      return;
    }

    if (event.target.closest('#addMapping')) {
      event.preventDefault();
      event.stopImmediatePropagation();
      const existingUnsaved = mappings.find(m => !m.saved);
      if (existingUnsaved) {
        showStatus();
        return;
      }

      hideStatus();
      mappings.unshift({
        id: nextId++,
        from: '',
        fromKey: '',
        to: '',
        toKey: 'NONE',
        saved: false,
        editing: false
      });
      recording = null;
      render();
      mappingList.scrollTo({ top: 0, behavior: 'auto' });
      const firstRecord = mappingList.querySelector('.unsaved .record-box');
      if (firstRecord) firstRecord.focus();
      return;
    }

    if (event.target.closest('#confirmCancel') || event.target === confirmBackdrop) {
      event.preventDefault();
      event.stopImmediatePropagation();
      closeDeleteConfirm();
      return;
    }

    if (event.target.closest('#confirmDelete')) {
      event.preventDefault();
      event.stopImmediatePropagation();
      if (pendingDeleteId === null) return;
      const result = parseResult(await callAhk('DeleteMapping', pendingDeleteId));
      if (!result.ok) {
        showStatus(result.message || '删除失败。');
        return;
      }
      mappings = mappings.filter(m => m.id !== pendingDeleteId);
      closeDeleteConfirm();
      hideStatus();
      render();
      return;
    }

    const button = event.target.closest('button[data-action]');
    if (!button) return;

    event.preventDefault();
    event.stopImmediatePropagation();
    const row = button.closest('.mapping-item');
    const id = Number(row.dataset.id);
    const item = mappings.find(m => m.id === id);
    if (!item) return;

    const action = button.dataset.action;
    if (action === 'record') {
      await beginCapture(item, button.dataset.field);
      return;
    }

    if (action === 'clear-target') {
      item.to = '';
      item.toKey = 'NONE';
      recording = null;
      await callAhk('CancelCapture');
      render();
      return;
    }

    if (action === 'save' || action === 'save-edit') {
      await saveItem(item);
      return;
    }

    if (action === 'edit') {
      item.editing = true;
      item.beforeEdit = {
        from: item.from,
        fromKey: item.fromKey,
        to: item.to,
        toKey: item.toKey
      };
      render();
      return;
    }

    if (action === 'cancel-edit') {
      if (item.beforeEdit) Object.assign(item, item.beforeEdit);
      item.editing = false;
      delete item.beforeEdit;
      recording = null;
      await callAhk('CancelCapture');
      render();
      return;
    }

    if (action === 'delete') {
      if (item.saved) {
        openDeleteConfirm(item);
        return;
      }

      mappings = mappings.filter(m => m.id !== id);
      recording = null;
      await callAhk('CancelCapture');
      hideStatus();
      render();
    }
  }

  document.addEventListener('click', event => {
    handleClick(event).catch(error => showStatus(error.message));
  }, true);

  document.addEventListener('pointermove', event => updateMappingPointerInside(event.target), true);
  document.addEventListener('pointerleave', () => updateMappingPointerInside(null), true);

  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape')
      return;

    if (aboutBackdrop.classList.contains('show')) {
      event.preventDefault();
      closeAbout();
      return;
    }

    if (settingsBackdrop.classList.contains('show')) {
      event.preventDefault();
      closeSettings();
      return;
    }

    if (confirmBackdrop.classList.contains('show')) {
      event.preventDefault();
      closeDeleteConfirm();
    }
  }, true);

  window.app = {
    receiveCaptureProgress(id, field, keyName, label) {
      const item = mappings.find(m => String(m.id) === String(id));
      if (!item) return;
      item[field] = label;
      item[`${field}Key`] = keyName;
      render();
    },

    receiveCapture(id, field, keyName, label) {
      const item = mappings.find(m => String(m.id) === String(id));
      if (!item) return;
      item[field] = label;
      item[`${field}Key`] = keyName;
      recording = null;
      mappingPointerInside = false;
      render();
    },

    captureCancelled() {
      recording = null;
      mappingPointerInside = false;
      render();
    },

    captureWarning(message) {
      showStatus(message);
    },

    backendError(message) {
      recording = null;
      mappingPointerInside = false;
      render();
      showStatus(message);
    }
  };

  async function initialize() {
    const state = parseResult(await callAhk('GetInitialState'));
    applyVersion(state.version || '1.6');
    settingsState = {
      autoStart: Boolean(state.settings?.autoStart),
      trayIcon: state.settings?.trayIcon !== false
    };
    renderSettings();
    mappings = (state.mappings || []).map(item => ({
      id: Number(item.id),
      from: item.fromLabel,
      fromKey: item.from,
      to: item.to === 'NONE' ? '' : item.toLabel,
      toKey: item.to,
      saved: true,
      editing: false
    }));
    nextId = mappings.reduce((highest, item) => Math.max(highest, item.id), 0) + 1;
    render();
  }

  initialize().catch(error => showStatus(error.message));
})();
