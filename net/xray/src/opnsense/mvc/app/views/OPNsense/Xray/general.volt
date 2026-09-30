{#
  os-xray: 通用设置
#}
<div class="content-box" style="padding-bottom: 1.5em;">
  <div class="col-md-12">
    <h4>{{ lang._('General settings') }}</h4>
    <table class="table table-condensed">
      <tr><td style="width:220px;">{{ lang._('Enabled') }}</td>
          <td><input type="checkbox" id="enabled"></td></tr>
      <tr><td>{{ lang._('Log level') }}</td>
          <td><select id="log_level" class="selectpicker">
            <option value="debug">debug</option><option value="info">info</option>
            <option value="warning">warning</option><option value="error">error</option>
            <option value="none">none</option></select></td></tr>
      <tr><td>{{ lang._('Access log path') }}</td>
          <td><input type="text" id="log_access" class="form-control" style="max-width:420px;" placeholder="{{ lang._('empty = disabled') }}"></td></tr>
      <tr><td>{{ lang._('Error log path') }}</td>
          <td><input type="text" id="log_error" class="form-control" style="max-width:420px;" placeholder="{{ lang._('empty = disabled') }}"></td></tr>
      <tr><td>{{ lang._('API listen (host:port)') }}</td>
          <td><input type="text" id="api_listen" class="form-control" style="max-width:420px;" placeholder="127.0.0.1:10085"></td></tr>
      <tr><td>{{ lang._('geosite.dat URL') }}</td>
          <td><input type="text" id="geosite_url" class="form-control" style="max-width:560px;"></td></tr>
      <tr><td>{{ lang._('geoip.dat URL') }}</td>
          <td><input type="text" id="geoip_url" class="form-control" style="max-width:560px;"></td></tr>
    </table>
    <button class="btn btn-primary" id="saveAct" type="button"><b>{{ lang._('Save') }}</b> <i id="saveAct_progress"></i></button>
  </div>
</div>

<div class="content-box" style="padding-bottom: 1.5em; margin-top: 15px;">
  <div class="col-md-12">
    <h4>{{ lang._('Service') }} <small id="svc_version" class="text-muted"></small></h4>
    <p>{{ lang._('Status') }}: <span id="svc_status" class="label label-default">-</span></p>
    <button class="btn btn-default" id="btn_start" type="button">{{ lang._('Start') }}</button>
    <button class="btn btn-default" id="btn_stop" type="button">{{ lang._('Stop') }}</button>
    <button class="btn btn-default" id="btn_restart" type="button">{{ lang._('Restart') }}</button>
    <button class="btn btn-primary" id="btn_apply" type="button" title="{{ lang._('Regenerate confdir JSON (routing sorted by priority), validate with xray -test, then restart') }}">
      {{ lang._('Apply configuration') }}</button>
    <button class="btn btn-default" id="btn_test" type="button">{{ lang._('Test config') }}</button>
    <pre id="svc_output" style="margin-top:10px; max-height:220px; overflow:auto; display:none;"></pre>
  </div>
</div>

<script>
$(document).ready(function() {
  var fields = ['enabled','log_level','log_access','log_error','api_listen','geosite_url','geoip_url'];
  function loadSettings() {
    ajaxCall('/api/xray/general/get', {}, function(data) {
      var g = data.general || {};
      fields.forEach(function(f) {
        var el = $('#' + f);
        if (f === 'enabled') { el.prop('checked', !!g[f]); }
        else { el.val(g[f] !== undefined ? g[f] : ''); }
      });
      $('.selectpicker').selectpicker('refresh');
    });
  }
  function showOut(data) {
    var txt = data.output || data.error || JSON.stringify(data);
    $('#svc_output').text(txt).show();
  }
  function refreshStatus() {
    ajaxCall('/api/xray/service/status', {}, function(data) {
      var s = $('#svc_status');
      s.text(data.status).removeClass('label-success label-danger label-default')
        .addClass(data.status === 'running' ? 'label-success' : 'label-danger');
    });
    ajaxCall('/api/xray/service/version', {}, function(data) {
      $('#svc_version').text(data.version || '');
    });
  }
  $('#saveAct').click(function() {
    var g = {};
    fields.forEach(function(f) {
      g[f] = (f === 'enabled') ? $('#' + f).is(':checked') : $('#' + f).val();
    });
    $('#saveAct_progress').addClass('fa fa-spinner fa-pulse');
    ajaxCall('/api/xray/general/set', {general: g}, function(data) {
      $('#saveAct_progress').removeClass('fa fa-spinner fa-pulse');
      if (data.result === 'saved') { stdDialogInform('OK', '{{ lang._('Saved') }}', '{{ lang._('Close') }}'); }
      else { stdDialogInform('Error', JSON.stringify(data.validations || data), '{{ lang._('Close') }}'); }
    });
  });
  $('#btn_start').click(function() { ajaxCall('/api/xray/service/start', {}, function(d){ showOut(d); refreshStatus(); }); });
  $('#btn_stop').click(function() { ajaxCall('/api/xray/service/stop', {}, function(d){ showOut(d); refreshStatus(); }); });
  $('#btn_restart').click(function() { ajaxCall('/api/xray/service/restart', {}, function(d){ showOut(d); refreshStatus(); }); });
  $('#btn_test').click(function() { ajaxCall('/api/xray/service/test', {}, function(d){ showOut(d); }); });
  $('#btn_apply').click(function() {
    $('#svc_output').text('{{ lang._('Applying, please wait...') }}').show();
    ajaxCall('/api/xray/service/reconfigure', {}, function(d){ showOut(d); refreshStatus(); });
  });
  loadSettings();
  refreshStatus();
});
</script>
