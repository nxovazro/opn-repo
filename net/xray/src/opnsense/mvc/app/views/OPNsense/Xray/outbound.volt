{#
  os-xray: 出站 + 订阅管理
#}
<div class="content-box" style="padding-bottom: 1.5em;">
  <div class="col-md-12">
    <div class="pull-right">
      <button class="btn btn-primary btn-sm" id="btn_add_sub" type="button"><i class="fa fa-plus"></i> {{ lang._('Add subscription') }}</button>
      <button class="btn btn-default btn-sm" id="btn_update_all" type="button"><i class="fa fa-refresh"></i> {{ lang._('Update all') }}</button>
    </div>
    <h4>{{ lang._('Subscriptions') }}</h4>
    <table class="table table-striped table-condensed" id="grid_sub">
      <thead><tr>
        <th>{{ lang._('Enabled') }}</th><th>{{ lang._('Name') }}</th><th>{{ lang._('URL') }}</th>
        <th>{{ lang._('Last update') }}</th><th>{{ lang._('Nodes') }}</th><th style="width:170px;">{{ lang._('Actions') }}</th>
      </tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>

<div class="content-box" style="padding-bottom: 1.5em; margin-top: 15px;">
  <div class="col-md-12">
    <div class="pull-right">
      <button class="btn btn-default btn-sm" id="btn_import_ob" type="button"><i class="fa fa-clipboard"></i> {{ lang._('Import from share links') }}</button>
      <button class="btn btn-primary btn-sm" id="btn_add_ob" type="button"><i class="fa fa-plus"></i> {{ lang._('Add outbound') }}</button>
    </div>
    <h4>{{ lang._('Outbounds') }} <small>{{ lang._('manual only; subscription nodes are merged automatically at apply time') }}</small></h4>
    <table class="table table-striped table-condensed" id="grid_ob">
      <thead><tr>
        <th>{{ lang._('Enabled') }}</th><th>{{ lang._('Tag') }}</th><th>{{ lang._('Protocol') }}</th>
        <th style="width:130px;">{{ lang._('Actions') }}</th>
      </tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>

<div id="dialog_sub" title="{{ lang._('Subscription') }}" style="display:none;">
  <table class="table table-condensed">
    <tr><td style="width:120px;">{{ lang._('Enabled') }}</td><td><input type="checkbox" id="s_enabled" checked></td></tr>
    <tr><td>{{ lang._('Name') }}</td><td><input type="text" id="s_name" class="form-control"></td></tr>
    <tr><td>{{ lang._('URL') }}</td><td><input type="text" id="s_url" class="form-control" style="max-width:520px;"></td></tr>
  </table>
</div>

<div id="dialog_ob" title="{{ lang._('Outbound') }}" style="display:none;">
  <table class="table table-condensed">
    <tr><td style="width:150px;">{{ lang._('Enabled') }}</td><td><input type="checkbox" id="o_enabled" checked></td></tr>
    <tr><td>{{ lang._('Tag') }}</td><td><input type="text" id="o_tag" class="form-control"></td></tr>
    <tr><td>{{ lang._('Protocol') }}</td><td><select id="o_protocol" class="selectpicker">
      <option value="freedom">freedom</option><option value="blackhole">blackhole</option>
      <option value="vless">vless</option><option value="vmess">vmess</option>
      <option value="trojan">trojan</option><option value="shadowsocks">shadowsocks</option>
      <option value="socks">socks</option><option value="http">http</option>
      <option value="wireguard">wireguard</option><option value="dns">dns</option>
    </select></td></tr>
    <tr><td colspan="2">{{ lang._('settings (JSON)') }}
      <textarea id="o_settings" class="form-control" rows="8"></textarea></td></tr>
    <tr><td colspan="2">{{ lang._('streamSettings (JSON)') }}
      <textarea id="o_stream" class="form-control" rows="6"></textarea></td></tr>
  </table>
</div>

<div id="dialog_import" title="{{ lang._('Import from share links') }}" style="display:none;">
  <p class="text-muted"><small>{{ lang._('Paste vless://, vmess://, trojan://, ss:// or socks:// links, one per line. They will be parsed into structured manual outbounds.') }}</small></p>
  <textarea id="i_links" class="form-control" rows="10" placeholder="vless://..."></textarea>
</div>

<script>
$(document).ready(function() {
  var subApi = '/api/xray/subscription', obApi = '/api/xray/outbound';
  var editingSub = null, editingOb = null;

  function esc(s) { return String(s === undefined ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function fmtJson(v) {
    if (v === undefined || v === null) return '';
    if (typeof v === 'string') return v;
    var s = JSON.stringify(v, null, 2);
    return s === '{}' || s === '[]' ? '' : s;
  }
  function parseJsonField(id, name) {
    var t = $(id).val().trim();
    if (t === '') return {};
    try { return JSON.parse(t); }
    catch (e) { throw name + ': JSON ' + e.message; }
  }
  function shortUrl(u) { return u.length > 48 ? u.substr(0, 48) + '...' : u; }

  function reloadSubs() {
    ajaxCall(subApi + '/list', {}, function(data) {
      var tb = $('#grid_sub tbody').empty();
      (data.rows || []).forEach(function(r) {
        var tr = $('<tr>');
        tr.append($('<td>').html('<input type="checkbox" class="sub_toggle" data-uuid="'+r.uuid+'"'+(r.enabled?' checked':'')+'>'));
        tr.append($('<td>').text(r.name));
        tr.append($('<td>').attr('title', r.url).text(shortUrl(r.url || '')));
        var lu = r.last_update || '-';
        if (r.last_error) lu += ' (' + r.last_error + ')';
        tr.append($('<td>').text(lu));
        tr.append($('<td>').text(r.count || 0));
        var act = $('<td>');
        act.append('<button class="btn btn-xs btn-default sub_update" data-uuid="'+r.uuid+'" title="{{ lang._('Fetch now') }}"><i class="fa fa-refresh"></i></button> ');
        act.append('<button class="btn btn-xs btn-default sub_edit" data-uuid="'+r.uuid+'"><i class="fa fa-pencil"></i></button> ');
        act.append('<button class="btn btn-xs btn-default sub_purge" data-uuid="'+r.uuid+'" title="{{ lang._('Remove imported nodes') }}"><i class="fa fa-eraser"></i></button> ');
        act.append('<button class="btn btn-xs btn-default sub_del" data-uuid="'+r.uuid+'"><i class="fa fa-trash"></i></button>');
        tr.append(act);
        tb.append(tr);
      });
    });
  }

  function reloadObs() {
    ajaxCall(obApi + '/list', {}, function(data) {
      var tb = $('#grid_ob tbody').empty();
      (data.rows || []).forEach(function(r) {
        var tr = $('<tr>');
        tr.append($('<td>').html('<input type="checkbox" class="ob_toggle" data-uuid="'+r.uuid+'"'+(r.enabled?' checked':'')+'>'));
        tr.append($('<td>').text(r.tag));
        tr.append($('<td>').text(r.protocol));
        var act = $('<td>');
        act.append('<button class="btn btn-xs btn-default ob_edit" data-uuid="'+r.uuid+'"><i class="fa fa-pencil"></i></button> ');
        act.append('<button class="btn btn-xs btn-default ob_del" data-uuid="'+r.uuid+'"><i class="fa fa-trash"></i></button>');
        tr.append(act);
        tb.append(tr);
      });
    });
  }

  /* ---- subscription dialog ---- */
  $('#dialog_sub').dialog({autoOpen: false, modal: true, width: 620, buttons: [
    {text: '{{ lang._('Save') }}', click: function() {
      var payload = {enabled: $('#s_enabled').is(':checked'), name: $('#s_name').val().trim(), url: $('#s_url').val().trim()};
      var url = editingSub ? subApi + '/set/' + editingSub : subApi + '/add';
      ajaxCall(url, payload, function(data) {
        if (data.result === 'saved') { $('#dialog_sub').dialog('close'); reloadSubs(); }
        else { stdDialogInform('Error', esc(JSON.stringify(data.validations || data)), '{{ lang._('Close') }}'); }
      });
    }},
    {text: '{{ lang._('Cancel') }}', click: function() { $(this).dialog('close'); }}
  ]});
  $('#btn_add_sub').click(function() {
    editingSub = null;
    $('#s_enabled').prop('checked', true); $('#s_name').val(''); $('#s_url').val('');
    $('#dialog_sub').dialog('open');
  });
  $('#grid_sub').on('click', '.sub_edit', function() {
    ajaxCall(subApi + '/get/' + $(this).data('uuid'), {}, function(data) {
      if (data.result === 'ok') {
        editingSub = data.item.uuid;
        $('#s_enabled').prop('checked', !!data.item.enabled);
        $('#s_name').val(data.item.name); $('#s_url').val(data.item.url);
        $('#dialog_sub').dialog('open');
      }
    });
  });
  $('#grid_sub').on('click', '.sub_del', function() {
    var uuid = $(this).data('uuid');
    stdDialogConfirm('{{ lang._('Confirm') }}', '{{ lang._('Delete this subscription and its cached nodes?') }}',
      '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall(subApi + '/del/' + uuid, {}, function() { reloadSubs(); });
    });
  });
  $('#grid_sub').on('click', '.sub_purge', function() {
    var uuid = $(this).data('uuid');
    stdDialogConfirm('{{ lang._('Confirm') }}', '{{ lang._('Remove this subscription\'s cached nodes? They will no longer be merged at apply time.') }}',
      '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall(subApi + '/purge/' + uuid, {}, function(d) {
        stdDialogInform('OK', d.purged ? '{{ lang._('Cache removed') }}' : '{{ lang._('No cache found') }}', '{{ lang._('Close') }}');
        reloadSubs();
      });
    });
  });
  $('#grid_sub').on('change', '.sub_toggle', function() {
    ajaxCall(subApi + '/toggle/' + $(this).data('uuid'), {}, function() { reloadSubs(); });
  });
  function doUpdate(uuid, btn) {
    if (btn) $(btn).find('i').addClass('fa-spin');
    ajaxCall(subApi + '/update', uuid ? {uuid: uuid} : {}, function(data) {
      if (btn) $(btn).find('i').removeClass('fa-spin');
      var rows = (data.updated || []).map(function(r) {
        return r.name + ': ' + r.imported + (r.error ? ' (' + r.error + ')' : '');
      }).join('\n');
      stdDialogInform(data.result === 'ok' ? 'OK' : 'Error', esc(rows || JSON.stringify(data)), '{{ lang._('Close') }}');
      reloadSubs();
    });
  }
  $('#grid_sub').on('click', '.sub_update', function() { doUpdate($(this).data('uuid'), this); });
  $('#btn_update_all').click(function() { doUpdate(null, this); });

  /* ---- outbound dialog ---- */
  $('#dialog_ob').dialog({autoOpen: false, modal: true, width: 640, buttons: [
    {text: '{{ lang._('Save') }}', click: function() {
      var payload;
      try {
        payload = {
          enabled: $('#o_enabled').is(':checked'),
          tag: $('#o_tag').val().trim(),
          protocol: $('#o_protocol').val(),
          settings: parseJsonField('#o_settings', 'settings'),
          streamSettings: parseJsonField('#o_stream', 'streamSettings')
        };
      } catch (e) { stdDialogInform('Error', esc(e), '{{ lang._('Close') }}'); return; }
      var url = editingOb ? obApi + '/set/' + editingOb : obApi + '/add';
      ajaxCall(url, payload, function(data) {
        if (data.result === 'saved') { $('#dialog_ob').dialog('close'); reloadObs(); }
        else { stdDialogInform('Error', esc(JSON.stringify(data.validations || data)), '{{ lang._('Close') }}'); }
      });
    }},
    {text: '{{ lang._('Cancel') }}', click: function() { $(this).dialog('close'); }}
  ]});
  $('#btn_add_ob').click(function() {
    editingOb = null;
    $('#o_enabled').prop('checked', true); $('#o_tag').val('');
    $('#o_protocol').val('freedom'); $('#o_settings').val(''); $('#o_stream').val('');
    $('.selectpicker').selectpicker('refresh');
    $('#dialog_ob').dialog('open');
  });
  $('#grid_ob').on('click', '.ob_edit', function() {
    ajaxCall(obApi + '/get/' + $(this).data('uuid'), {}, function(data) {
      if (data.result === 'ok') {
        var it = data.item;
        editingOb = it.uuid;
        $('#o_enabled').prop('checked', !!it.enabled);
        $('#o_tag').val(it.tag); $('#o_protocol').val(it.protocol);
        $('#o_settings').val(fmtJson(it.settings)); $('#o_stream').val(fmtJson(it.streamSettings));
        $('.selectpicker').selectpicker('refresh');
        $('#dialog_ob').dialog('open');
      }
    });
  });
  $('#grid_ob').on('click', '.ob_del', function() {
    var uuid = $(this).data('uuid');
    stdDialogConfirm('{{ lang._('Confirm') }}', '{{ lang._('Delete this outbound?') }}', '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall(obApi + '/del/' + uuid, {}, function() { reloadObs(); });
    });
  });
  $('#grid_ob').on('change', '.ob_toggle', function() {
    ajaxCall(obApi + '/toggle/' + $(this).data('uuid'), {}, function() { reloadObs(); });
  });

  /* ---- import from share links ---- */
  $('#dialog_import').dialog({autoOpen: false, modal: true, width: 640, buttons: [
    {text: '{{ lang._('Import') }}', click: function() {
      var links = $('#i_links').val();
      if (!links.trim()) { return; }
      ajaxCall(obApi + '/import', {links: links}, function(data) {
        if (data.result === 'saved') {
          $('#dialog_import').dialog('close');
          $('#i_links').val('');
          stdDialogInform('OK',
            '{{ lang._('Added') }}: ' + data.added + ' / {{ lang._('Skipped') }}: ' + data.skipped,
            '{{ lang._('Close') }}');
          reloadObs();
        } else {
          stdDialogInform('Error', esc(data.error || JSON.stringify(data)), '{{ lang._('Close') }}');
        }
      });
    }},
    {text: '{{ lang._('Cancel') }}', click: function() { $(this).dialog('close'); }}
  ]});
  $('#btn_import_ob').click(function() { $('#dialog_import').dialog('open'); });

  reloadSubs();
  reloadObs();
});
</script>
