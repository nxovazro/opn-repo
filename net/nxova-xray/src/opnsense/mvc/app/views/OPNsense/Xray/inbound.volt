{#
  os-xray: 入站编辑
#}
<div class="content-box" style="padding-bottom: 1.5em;">
  <div class="col-md-12">
    <div class="pull-right">
      <button class="btn btn-primary btn-sm" id="btn_add" type="button"><i class="fa fa-plus"></i> {{ lang._('Add') }}</button>
    </div>
    <h4>{{ lang._('Inbounds') }}</h4>
    <table class="table table-striped table-condensed" id="grid">
      <thead><tr>
        <th>{{ lang._('Enabled') }}</th><th>{{ lang._('Tag') }}</th><th>{{ lang._('Protocol') }}</th>
        <th>{{ lang._('Listen') }}</th><th>{{ lang._('Port') }}</th><th style="width:130px;">{{ lang._('Actions') }}</th>
      </tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>

<div class="modal fade" id="dialog" tabindex="-1" role="dialog">
  <div class="modal-dialog" role="document">
    <div class="modal-content">
      <div class="modal-header">
        <button type="button" class="close" data-dismiss="modal" aria-label="{{ lang._('Close') }}"><span aria-hidden="true">&times;</span></button>
        <h4 class="modal-title">{{ lang._('Inbound') }}</h4>
      </div>
      <div class="modal-body">
      <table class="table table-condensed">
        <tr><td style="width:150px;">{{ lang._('Enabled') }}</td><td><input type="checkbox" id="f_enabled" checked></td></tr>
        <tr><td>{{ lang._('Tag') }}</td><td><input type="text" id="f_tag" class="form-control"></td></tr>
        <tr><td>{{ lang._('Protocol') }}</td><td><select id="f_protocol" class="selectpicker">
          <option value="dokodemo-door">dokodemo-door</option><option value="socks">socks</option>
          <option value="http">http</option><option value="vless">vless</option>
          <option value="vmess">vmess</option><option value="trojan">trojan</option>
          <option value="shadowsocks">shadowsocks</option><option value="wireguard">wireguard</option>
        </select></td></tr>
        <tr><td>{{ lang._('Listen') }}</td><td><input type="text" id="f_listen" class="form-control" placeholder="127.0.0.1"></td></tr>
        <tr><td>{{ lang._('Port') }}</td><td><input type="number" id="f_port" class="form-control" min="1" max="65535"></td></tr>
        <tr><td>{{ lang._('Sniffing') }}</td><td><input type="checkbox" id="f_sniff"> <span class="text-muted">destOverride http,tls</span></td></tr>
        <tr><td colspan="2">{{ lang._('settings (JSON)') }}
          <textarea id="f_settings" class="form-control" rows="6" placeholder='{"auth":"noauth","udp":true}'></textarea></td></tr>
        <tr><td colspan="2">{{ lang._('streamSettings (JSON)') }}
          <textarea id="f_stream" class="form-control" rows="6" placeholder='{"network":"ws","wsSettings":{"path":"/"}}'></textarea></td></tr>
      </table>
      </div>
      <div class="modal-footer">
        <button type="button" class="btn btn-default" data-dismiss="modal">{{ lang._('Cancel') }}</button>
        <button type="button" class="btn btn-primary" id="btn_save">{{ lang._('Save') }}</button>
      </div>
    </div>
  </div>
</div>

<script>
$(document).ready(function() {
  var api = '/api/xray/inbound';
  var editing = null;

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
  function esc(s) { return String(s === undefined ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

  function reload() {
    ajaxCall(api + '/list', {}, function(data) {
      var tb = $('#grid tbody').empty();
      (data.rows || []).forEach(function(r) {
        var tr = $('<tr>');
        tr.append($('<td>').html('<input type="checkbox" class="row_toggle" data-uuid="'+r.uuid+'"'+(r.enabled?' checked':'')+'>'));
        tr.append($('<td>').text(r.tag));
        tr.append($('<td>').text(r.protocol));
        tr.append($('<td>').text(r.listen || ''));
        tr.append($('<td>').text(r.port));
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
    $('#f_enabled').prop('checked', item ? !!item.enabled : true);
    $('#f_tag').val(item ? item.tag : '');
    $('#f_protocol').val(item ? item.protocol : 'dokodemo-door');
    $('#f_listen').val(item ? (item.listen || '') : '127.0.0.1');
    $('#f_port').val(item ? item.port : '');
    $('#f_sniff').prop('checked', !!(item && item.sniffing && item.sniffing.enabled));
    $('#f_settings').val(fmtJson(item && item.settings));
    $('#f_stream').val(fmtJson(item && item.streamSettings));
    $('.selectpicker').selectpicker('refresh');
    $('#dialog').modal('show');
  }

  $('#btn_save').click(function() {
      var payload;
      try {
        payload = {
          enabled: $('#f_enabled').is(':checked'),
          tag: $('#f_tag').val().trim(),
          protocol: $('#f_protocol').val(),
          listen: $('#f_listen').val().trim(),
          port: parseInt($('#f_port').val(), 10),
          settings: parseJsonField('#f_settings', 'settings'),
          streamSettings: parseJsonField('#f_stream', 'streamSettings'),
          sniffing: {enabled: $('#f_sniff').is(':checked'), destOverride: ['http','tls']}
        };
      } catch (e) { stdDialogInform('Error', esc(e), '{{ lang._('Close') }}'); return; }
      var url = editing ? api + '/set/' + editing : api + '/add';
      ajaxCall(url, payload, function(data) {
        if (data.result === 'saved') { $('#dialog').modal('hide'); reload(); }
        else { stdDialogInform('Error', esc(JSON.stringify(data.validations || data)), '{{ lang._('Close') }}'); }
      });
  });

  $('#btn_add').click(function() { openDialog(null); });
  $('#grid').on('click', '.row_edit', function() {
    ajaxCall(api + '/get/' + $(this).data('uuid'), {}, function(data) {
      if (data.result === 'ok') openDialog(data.item);
    });
  });
  $('#grid').on('click', '.row_del', function() {
    var uuid = $(this).data('uuid');
    stdDialogConfirm('{{ lang._('Confirm') }}', '{{ lang._('Delete this inbound?') }}', '{{ lang._('Yes') }}', '{{ lang._('No') }}', function() {
      ajaxCall(api + '/del/' + uuid, {}, function() { reload(); });
    });
  });
  $('#grid').on('change', '.row_toggle', function() {
    ajaxCall(api + '/toggle/' + $(this).data('uuid'), {}, function() { reload(); });
  });

  reload();
});
</script>
