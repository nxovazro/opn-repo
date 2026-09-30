{#
  os-xray: 路由编辑（按优先级排序，应用时按优先级写入）
#}
<div class="content-box" style="padding-bottom: 1.5em;">
  <div class="col-md-12">
    <div class="pull-right">
      <button class="btn btn-default btn-sm" id="btn_apply" type="button" title="{{ lang._('Regenerate confdir JSON with rules in priority order, validate, restart') }}">
        <i class="fa fa-check"></i> {{ lang._('Apply') }}</button>
      <button class="btn btn-primary btn-sm" id="btn_add" type="button"><i class="fa fa-plus"></i> {{ lang._('Add rule') }}</button>
    </div>
    <h4>{{ lang._('Routing rules') }} <small>{{ lang._('lower priority value = matched first') }}</small></h4>
    <table class="table table-striped table-condensed" id="grid">
      <thead><tr>
        <th style="width:70px;">{{ lang._('Priority') }}</th><th style="width:60px;">{{ lang._('On') }}</th>
        <th>{{ lang._('Name') }}</th><th>{{ lang._('Match') }}</th><th>{{ lang._('Target') }}</th>
        <th style="width:170px;">{{ lang._('Actions') }}</th>
      </tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>

<div id="dialog" title="{{ lang._('Routing rule') }}" style="display:none;">
  <table class="table table-condensed">
    <tr>
      <td style="width:140px;">{{ lang._('Enabled') }}</td><td><input type="checkbox" id="r_enabled" checked></td>
      <td style="width:100px;">{{ lang._('Priority') }}</td>
      <td><input type="number" id="r_priority" class="form-control" value="100" step="1"></td>
    </tr>
    <tr><td>{{ lang._('Name') }}</td><td colspan="3"><input type="text" id="r_name" class="form-control" placeholder="{{ lang._('description only, not written to xray config') }}"></td></tr>
    <tr><td>{{ lang._('Domain') }}<br><span class="text-muted"><small>geosite {{ lang._('multi-select') }}</small></span></td>
      <td colspan="3"><select id="r_geosite" class="selectpicker" multiple data-live-search="true" data-width="100%"></select></td></tr>
    <tr><td>{{ lang._('Domain (manual)') }}<br><span class="text-muted"><small>{{ lang._('one per line: domain:/full:/keyword:/regexp: or bare domain') }}</small></span></td>
      <td colspan="3"><textarea id="r_domain_manual" class="form-control" rows="2"></textarea></td></tr>
    <tr><td>{{ lang._('IP') }}<br><span class="text-muted"><small>{{ lang._('one per line: geoip:XX or CIDR') }}</small></span></td>
      <td colspan="3"><textarea id="r_ip" class="form-control" rows="2"></textarea></td></tr>
    <tr>
      <td>{{ lang._('Port') }}</td><td><input type="text" id="r_port" class="form-control" placeholder="80,443"></td>
      <td>{{ lang._('Network') }}</td>
      <td><select id="r_network" class="selectpicker" multiple>
        <option value="tcp">tcp</option><option value="udp">udp</option></select></td>
    </tr>
    <tr>
      <td>{{ lang._('Protocol') }}<br><span class="text-muted"><small>{{ lang._('comma separated') }}</small></span></td>
      <td><input type="text" id="r_protocol" class="form-control" placeholder="tls,http,bittorrent"></td>
      <td>{{ lang._('InboundTag') }}</td>
      <td><select id="r_inboundTag" class="selectpicker" multiple data-width="100%"></select></td>
    </tr>
    <tr>
      <td>{{ lang._('Source') }}<br><span class="text-muted"><small>{{ lang._('comma separated IP/CIDR') }}</small></span></td>
      <td><input type="text" id="r_source" class="form-control"></td>
      <td>{{ lang._('User') }}</td><td><input type="text" id="r_user" class="form-control" placeholder="{{ lang._('comma separated emails') }}"></td>
    </tr>
    <tr><td>{{ lang._('Target outbound') }}</td>
      <td colspan="3"><select id="r_outboundTag" class="selectpicker" data-live-search="true" data-width="100%"></select></td></tr>
    <tr><td colspan="4">{{ lang._('attrs (JSON, optional)') }}
      <textarea id="r_attrs" class="form-control" rows="2" placeholder='{"attr1":["val"]}'></textarea></td></tr>
  </table>
</div>

<script>
$(document).ready(function() {
  var api = '/api/xray/routing';
  var editing = null;
  var geoCats = [];   // [{name, domains}]

  /* 常用分类（大写命名，来自当前 domain-list-community；仅显示 dat 中实际存在的） */
  var COMMON = ['GEOLOCATION-CN','PRIVATE','GOOGLE','YOUTUBE','NETFLIX','TELEGRAM','APPLE',
    'MICROSOFT','GITHUB','CLOUDFLARE','OPENAI','ANTHROPIC','GEMINI','DISNEY','HBO','SPOTIFY',
    'TWITTER','FACEBOOK','AMAZON','STEAM','TIKTOK','CATEGORY-ADS-ALL','CATEGORY-AI-ALL'];

  function esc(s) { return String(s === undefined ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function csv(v) { return Array.isArray(v) ? v.join(',') : (v || ''); }

  function matchSummary(r) {
    var parts = [];
    if (r.domain && r.domain.length) parts.push(r.domain.slice(0,2).join(' ') + (r.domain.length > 2 ? ' (+'+(r.domain.length-2)+')' : ''));
    if (r.ip && r.ip.length) parts.push(r.ip.slice(0,2).join(' ') + (r.ip.length > 2 ? ' (+'+(r.ip.length-2)+')' : ''));
    if (r.port) parts.push('port:' + r.port);
    if (r.inboundTag && r.inboundTag.length) parts.push('in:' + r.inboundTag.join(','));
    return parts.join(' | ') || '-';
  }

  function reload() {
    ajaxCall(api + '/list', {}, function(data) {
      var tb = $('#grid tbody').empty();
      (data.rows || []).forEach(function(r, idx, arr) {
        var tr = $('<tr>').toggleClass('text-muted', !r.enabled);
        tr.append($('<td>').html('<b>' + esc(r.priority) + '</b>'));
        tr.append($('<td>').html('<input type="checkbox" class="row_toggle" data-uuid="'+r.uuid+'"'+(r.enabled?' checked':'')+'>'));
        tr.append($('<td>').text(r.name || '-'));
        tr.append($('<td>').html('<small>' + esc(matchSummary(r)) + '</small>'));
        tr.append($('<td>').html('<span class="label label-primary">' + esc(r.outboundTag || '-') + '</span>'));
        var act = $('<td>');
        if (idx > 0) act.append('<button class="btn btn-xs btn-default row_up" data-uuid="'+r.uuid+'" title="{{ lang._('Move up (higher precedence)') }}"><i class="fa fa-arrow-up"></i></button> ');
        if (idx < arr.length - 1) act.append('<button class="btn btn-xs btn-default row_down" data-uuid="'+r.uuid+'" title="{{ lang._('Move down') }}"><i class="fa fa-arrow-down"></i></button> ');
        act.append('<button class="btn btn-xs btn-default row_edit" data-uuid="'+r.uuid+'"><i class="fa fa-pencil"></i></button> ');
        act.append('<button class="btn btn-xs btn-default row_del" data-uuid="'+r.uuid+'"><i class="fa fa-trash"></i></button>');
        tr.append(act);
        tb.append(tr);
      });
    });
  }

  function loadGeosite(selected) {
    ajaxCall('/api/xray/geosite/categories', {}, function(data) {
      geoCats = data.categories || [];
      var names = geoCats.map(function(c){ return c.name; });
      var common = COMMON.filter(function(n){ return names.indexOf(n) >= 0; });
      var rest = names.filter(function(n){ return common.indexOf(n) < 0; });
      var sel = $('#r_geosite').empty();
      var g1 = $('<optgroup label="{{ lang._('Common') }}">');
      common.forEach(function(n){ g1.append($('<option>').val('geosite:'+n).text('geosite:'+n)); });
      var g2 = $('<optgroup label="{{ lang._('All') }} (' + rest.length + ')">');
      rest.forEach(function(n){ g2.append($('<option>').val('geosite:'+n).text('geosite:'+n)); });
      sel.append(g1).append(g2);
      if (selected) sel.val(selected);
      sel.selectpicker('refresh');
    });
  }

  function loadInboundTags(selected) {
    ajaxCall('/api/xray/inbound/list', {}, function(data) {
      var sel = $('#r_inboundTag').empty();
      (data.rows || []).forEach(function(r){ sel.append($('<option>').val(r.tag).text(r.tag)); });
      if (selected) sel.val(selected);
      sel.selectpicker('refresh');
    });
  }

  function loadTargets(selected) {
    ajaxCall(api + '/targets', {}, function(data) {
      var sel = $('#r_outboundTag').empty();
      ['direct','proxy','block'].forEach(function(t){ sel.append($('<option>').val(t).text(t)); });
      (data.tags || []).forEach(function(t){ if (['direct','proxy','block'].indexOf(t) < 0) sel.append($('<option>').val(t).text(t)); });
      if (selected) sel.val(selected);
      sel.selectpicker('refresh');
    });
  }

  function splitLines(t) {
    return t.split('\n').map(function(s){ return s.trim(); }).filter(function(s){ return s !== ''; });
  }
  function normDomain(line) {
    if (/^(geosite|domain|full|keyword|regexp|ext):/.test(line)) return line;
    return 'domain:' + line;
  }

  function openDialog(item) {
    editing = item ? item.uuid : null;
    var geositeSel = [], manual = [];
    if (item && item.domain) {
      item.domain.forEach(function(d) {
        if (/^geosite:/.test(d)) geositeSel.push(d); else manual.push(d);
      });
    }
    $('#r_enabled').prop('checked', item ? !!item.enabled : true);
    $('#r_priority').val(item ? item.priority : 100);
    $('#r_name').val(item ? (item.name || '') : '');
    $('#r_domain_manual').val(manual.join('\n'));
    $('#r_ip').val(item && item.ip ? item.ip.join('\n') : '');
    $('#r_port').val(item ? (item.port || '') : '');
    $('#r_protocol').val(csv(item && item.protocol));
    $('#r_source').val(csv(item && item.source));
    $('#r_user').val(csv(item && item.user));
    $('#r_attrs').val(item && item.attrs && Object.keys(item.attrs).length ? JSON.stringify(item.attrs, null, 2) : '');
    loadGeosite(geositeSel);
    loadInboundTags(item && item.inboundTag);
    $('#r_network').val(item && item.network ? String(item.network).split(',') : []);
    $('#r_network').selectpicker('refresh');
    loadTargets(item && item.outboundTag);
    $('#dialog').dialog('open');
  }

  $('#dialog').dialog({autoOpen: false, modal: true, width: 760, buttons: [
    {text: '{{ lang._('Save') }}', click: function() {
      var payload;
      try {
        var at = $('#r_attrs').val().trim();
        var geos = $('#r_geosite').val() || [];
        var manual = splitLines($('#r_domain_manual').val()).map(normDomain);
        payload = {
          enabled: $('#r_enabled').is(':checked'),
          priority: parseInt($('#r_priority').val(), 10) || 0,
          name: $('#r_name').val().trim(),
          type: 'field',
          domain: geos.concat(manual),
          ip: splitLines($('#r_ip').val()),
          port: $('#r_port').val().trim(),
          network: ($('#r_network').val() || []).join(','),
          protocol: $('#r_protocol').val().split(',').map(function(s){return s.trim();}).filter(Boolean),
          inboundTag: $('#r_inboundTag').val() || [],
          source: $('#r_source').val().split(',').map(function(s){return s.trim();}).filter(Boolean),
          user: $('#r_user').val().split(',').map(function(s){return s.trim();}).filter(Boolean),
          attrs: at ? JSON.parse(at) : {},
          outboundTag: $('#r_outboundTag').val() || ''
        };
      } catch (e) { stdDialogInform('Error', esc('attrs: JSON ' + e.message), '{{ lang._('Close') }}'); return; }
      var url = editing ? api + '/set/' + editing : api + '/add';
      ajaxCall(url, payload, function(data) {
        if (data.result === 'saved') { $('#dialog').dialog('close'); reload(); }
        else { stdDialogInform('Error', esc(JSON.stringify(data.validations || data)), '{{ lang._('Close') }}'); }
      });
    }},
    {text: '{{ lang._('Cancel') }}', click: function() { $(this).dialog('close'); }}
  ]});

  $('#btn_add').click(function() { openDialog(null); });
  $('#btn_apply').click(function() {
    stdDialogConfirm('{{ lang._('Confirm') }}',
      '{{ lang._('Regenerate confdir JSON with rules in priority order, validate with xray -test and restart xray?') }}',
      '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall('/api/xray/service/reconfigure', {}, function(data) {
        stdDialogInform(data.result === 'ok' ? 'OK' : 'Error',
          esc(data.error || JSON.stringify(data.files || data)), '{{ lang._('Close') }}');
      });
    });
  });
  $('#grid').on('click', '.row_edit', function() {
    ajaxCall(api + '/get/' + $(this).data('uuid'), {}, function(data) {
      if (data.result === 'ok') openDialog(data.item);
    });
  });
  $('#grid').on('click', '.row_del', function() {
    var uuid = $(this).data('uuid');
    stdDialogConfirm('{{ lang._('Confirm') }}', '{{ lang._('Delete this rule?') }}', '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall(api + '/del/' + uuid, {}, function() { reload(); });
    });
  });
  $('#grid').on('change', '.row_toggle', function() {
    ajaxCall(api + '/toggle/' + $(this).data('uuid'), {}, function() { reload(); });
  });
  $('#grid').on('click', '.row_up', function() {
    ajaxCall(api + '/move/' + $(this).data('uuid'), {direction: 'up'}, function() { reload(); });
  });
  $('#grid').on('click', '.row_down', function() {
    ajaxCall(api + '/move/' + $(this).data('uuid'), {direction: 'down'}, function() { reload(); });
  });

  reload();
});
</script>
