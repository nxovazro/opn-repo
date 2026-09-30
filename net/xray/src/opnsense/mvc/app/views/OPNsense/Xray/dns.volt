{#
  os-xray: DNS 分流（xray dns section + 自动 dns-in 入站）
#}
<div class="content-box" style="padding-bottom: 1.5em;">
  <div class="col-md-12">
    <div class="pull-right">
      <button class="btn btn-default btn-sm" id="btn_apply" type="button" title="{{ lang._('Regenerate confdir JSON, validate, restart') }}">
        <i class="fa fa-check"></i> {{ lang._('Apply') }}</button>
    </div>
    <h4>{{ lang._('DNS settings') }}</h4>
    <table class="table table-condensed">
      <tr><td style="width:220px;">{{ lang._('Enabled') }}</td>
          <td><input type="checkbox" id="d_enabled"></td></tr>
      <tr><td>{{ lang._('Listen') }}</td>
          <td><input type="text" id="d_listen" class="form-control" style="max-width:280px;" placeholder="127.0.0.1"></td></tr>
      <tr><td>{{ lang._('Port') }}</td>
          <td><input type="number" id="d_port" class="form-control" style="max-width:160px;" value="53" min="1" max="65535"></td></tr>
      <tr><td>{{ lang._('Query strategy') }}</td>
          <td><select id="d_queryStrategy" class="selectpicker">
            <option value="UseIP">UseIP</option><option value="UseIPv4">UseIPv4</option><option value="UseIPv6">UseIPv6</option></select></td></tr>
      <tr><td>{{ lang._('Disable cache') }}</td>
          <td><input type="checkbox" id="d_disableCache"></td></tr>
      <tr><td>{{ lang._('Disable fallback') }}</td>
          <td><input type="checkbox" id="d_disableFallback"></td></tr>
      <tr><td>{{ lang._('Client IP') }}</td>
          <td><input type="text" id="d_clientIp" class="form-control" style="max-width:280px;" placeholder="{{ lang._('optional, sent to the DNS server') }}"></td></tr>
    </table>
    <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
    <p class="text-muted" style="margin-top:8px;"><small>
      {{ lang._('When enabled, apply generates a "dns-in" dokodemo-door inbound on listen:port, a "dns" outbound and a first-match routing rule wiring them together.') }}
    </small></p>
  </div>
</div>

<div class="content-box" style="padding-bottom: 1.5em; margin-top: 15px;">
  <div class="col-md-12">
    <div class="pull-right">
      <button class="btn btn-primary btn-sm" id="btn_add" type="button"><i class="fa fa-plus"></i> {{ lang._('Add server') }}</button>
    </div>
    <h4>{{ lang._('DNS servers') }}</h4>
    <table class="table table-striped table-condensed" id="grid">
      <thead><tr>
        <th style="width:60px;">{{ lang._('On') }}</th><th>{{ lang._('Address') }}</th>
        <th>{{ lang._('Domains') }}</th><th>{{ lang._('Expect IPs') }}</th>
        <th style="width:130px;">{{ lang._('Actions') }}</th>
      </tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>

<div id="dialog" title="{{ lang._('DNS server') }}" style="display:none;">
  <table class="table table-condensed">
    <tr><td style="width:150px;">{{ lang._('Enabled') }}</td>
        <td><input type="checkbox" id="s_enabled" checked></td></tr>
    <tr><td>{{ lang._('Address') }}</td>
        <td><input type="text" id="s_address" class="form-control" placeholder="8.8.8.8 / https://dns.example/dns-query / 8.8.8.8#dns.example"></td></tr>
    <tr><td>{{ lang._('Port') }}</td>
        <td><input type="number" id="s_port" class="form-control" value="53" min="1" max="65535" style="max-width:160px;"></td></tr>
    <tr><td>{{ lang._('Domains') }}<br><span class="text-muted"><small>{{ lang._('one per line; empty = default server') }}</small></span></td>
        <td><textarea id="s_domains" class="form-control" rows="3" placeholder="geosite:cn"></textarea></td></tr>
    <tr><td>{{ lang._('Expect IPs') }}<br><span class="text-muted"><small>{{ lang._('one per line: geoip:cn or CIDR') }}</small></span></td>
        <td><textarea id="s_expectIPs" class="form-control" rows="2"></textarea></td></tr>
    <tr><td>{{ lang._('Skip fallback') }}</td>
        <td><input type="checkbox" id="s_skipFallback"></td></tr>
  </table>
</div>

<script>
$(document).ready(function() {
  var api = '/api/xray/dnsserver';
  var editing = null;

  function esc(s) { return String(s === undefined ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }
  function splitLines(t) {
    return (t || '').split('\n').map(function(s){ return s.trim(); }).filter(function(s){ return s !== ''; });
  }

  function loadSettings() {
    ajaxCall('/api/xray/dns/get', {}, function(data) {
      var d = data.dns || {};
      $('#d_enabled').prop('checked', !!d.enabled);
      $('#d_listen').val(d.listen !== undefined ? d.listen : '127.0.0.1');
      $('#d_port').val(d.port !== undefined ? d.port : 53);
      $('#d_queryStrategy').val(d.queryStrategy || 'UseIP');
      $('#d_disableCache').prop('checked', !!d.disableCache);
      $('#d_disableFallback').prop('checked', !!d.disableFallback);
      $('#d_clientIp').val(d.clientIp || '');
      $('.selectpicker').selectpicker('refresh');
    });
  }

  $('#saveAct').click(function() {
    var payload = {
      enabled: $('#d_enabled').is(':checked'),
      listen: $('#d_listen').val().trim(),
      port: parseInt($('#d_port').val(), 10) || 53,
      queryStrategy: $('#d_queryStrategy').val(),
      disableCache: $('#d_disableCache').is(':checked'),
      disableFallback: $('#d_disableFallback').is(':checked'),
      clientIp: $('#d_clientIp').val().trim()
    };
    ajaxCall('/api/xray/dns/set', {dns: payload}, function(data) {
      if (data.result === 'saved') { stdDialogInform('OK', '{{ lang._('Saved') }}', '{{ lang._('Close') }}'); }
      else { stdDialogInform('Error', esc(JSON.stringify(data.validations || data)), '{{ lang._('Close') }}'); }
    });
  });

  function reload() {
    ajaxCall(api + '/list', {}, function(data) {
      var tb = $('#grid tbody').empty();
      (data.rows || []).forEach(function(r) {
        var tr = $('<tr>').toggleClass('text-muted', !r.enabled);
        tr.append($('<td>').html('<input type="checkbox" class="row_toggle" data-uuid="'+r.uuid+'"'+(r.enabled?' checked':'')+'>'));
        tr.append($('<td>').html('<b>' + esc(r.address) + '</b>' + (r.port && r.port !== 53 ? ':' + esc(r.port) : '') + (r.skipFallback ? ' <span class="label label-default">no-fallback</span>' : '')));
        tr.append($('<td>').html('<small>' + esc((r.domains || []).slice(0,3).join(' ') + ((r.domains||[]).length > 3 ? ' (+'+((r.domains||[]).length-3)+')' : '')) + '</small>'));
        tr.append($('<td>').html('<small>' + esc((r.expectIPs || []).join(' ')) + '</small>'));
        var act = $('<td>');
        act.append('<button class="btn btn-xs btn-default row_edit" data-uuid="'+r.uuid+'"><i class="fa fa-pencil"></i></button> ');
        act.append('<button class="btn btn-xs btn-default row_del" data-uuid="'+r.uuid+'"><i class="fa fa-trash"></i></button>');
        tr.append(act);
        tb.append(tr);
      });
    });
  }

  function openDialog(item) {
    editing = item ? item.uuid : null;
    $('#s_enabled').prop('checked', item ? !!item.enabled : true);
    $('#s_address').val(item ? (item.address || '') : '');
    $('#s_port').val(item ? (item.port || 53) : 53);
    $('#s_domains').val(item && item.domains ? item.domains.join('\n') : '');
    $('#s_expectIPs').val(item && item.expectIPs ? item.expectIPs.join('\n') : '');
    $('#s_skipFallback').prop('checked', item ? !!item.skipFallback : false);
    $('#dialog').dialog('open');
  }

  $('#dialog').dialog({autoOpen: false, modal: true, width: 640, buttons: [
    {text: '{{ lang._('Save') }}', click: function() {
      var payload = {
        enabled: $('#s_enabled').is(':checked'),
        address: $('#s_address').val().trim(),
        port: parseInt($('#s_port').val(), 10) || 53,
        domains: splitLines($('#s_domains').val()),
        expectIPs: splitLines($('#s_expectIPs').val()),
        skipFallback: $('#s_skipFallback').is(':checked')
      };
      var url = editing ? api + '/set/' + editing : api + '/add';
      ajaxCall(url, payload, function(data) {
        if (data.result === 'saved') { $('#dialog').dialog('close'); reload(); }
        else { stdDialogInform('Error', esc(JSON.stringify(data.validations || data)), '{{ lang._('Close') }}'); }
      });
    }},
    {text: '{{ lang._('Cancel') }}', click: function() { $(this).dialog('close'); }}
  ]});

  $('#btn_add').click(function() { openDialog(null); });
  $('#grid').on('click', '.row_edit', function() {
    ajaxCall(api + '/get/' + $(this).data('uuid'), {}, function(data) {
      if (data.result === 'ok') openDialog(data.item);
    });
  });
  $('#grid').on('click', '.row_del', function() {
    var uuid = $(this).data('uuid');
    stdDialogConfirm('{{ lang._('Confirm') }}', '{{ lang._('Delete this DNS server?') }}', '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall(api + '/del/' + uuid, {}, function() { reload(); });
    });
  });
  $('#grid').on('change', '.row_toggle', function() {
    ajaxCall(api + '/toggle/' + $(this).data('uuid'), {}, function() { reload(); });
  });
  $('#btn_apply').click(function() {
    stdDialogConfirm('{{ lang._('Confirm') }}',
      '{{ lang._('Regenerate confdir JSON, validate with xray -test and restart xray?') }}',
      '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall('/api/xray/service/reconfigure', {}, function(data) {
        var msg = data.result === 'ok'
          ? JSON.stringify(data.files || data) + (data.warnings ? '\n' + data.warnings.join('\n') : '')
          : (data.error || JSON.stringify(data));
        stdDialogInform(data.result === 'ok' ? 'OK' : 'Error', esc(msg), '{{ lang._('Close') }}');
      });
    });
  });

  loadSettings();
  reload();
});
</script>
