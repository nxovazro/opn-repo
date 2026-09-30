{#
  os-xray: geosite.dat 管理与分类浏览
#}
<div class="content-box" style="padding-bottom: 1.5em;">
  <div class="col-md-12">
    <h4>{{ lang._('geosite.dat') }}</h4>
    <p>
      {{ lang._('Source') }}: <code id="g_source">-</code><br>
      {{ lang._('Extracted') }}: <span id="g_updated">-</span><br>
      {{ lang._('Categories') }}: <b id="g_count">-</b>
    </p>
    <button class="btn btn-default btn-sm" id="btn_refresh" type="button"><i class="fa fa-list"></i> {{ lang._('Re-extract categories') }}</button>
    <label class="checkbox-inline" style="margin-left:12px;"><input type="checkbox" id="dl_geosite" checked> geosite.dat</label>
    <label class="checkbox-inline"><input type="checkbox" id="dl_geoip"> geoip.dat</label>
    <button class="btn btn-default btn-sm" id="btn_download" type="button"><i class="fa fa-download"></i> {{ lang._('Download from URL') }}</button>
    <span class="btn btn-default btn-sm" style="position:relative; overflow:hidden; margin-left:8px;">
      <i class="fa fa-upload"></i> {{ lang._('Upload geosite.dat') }}
      <input type="file" id="file_upload" accept=".dat" style="position:absolute; top:0; right:0; opacity:0; cursor:pointer;">
    </span>
    <span id="g_msg" class="text-muted" style="margin-left:10px;"></span>
  </div>
</div>

<div class="content-box" style="padding-bottom: 1.5em; margin-top: 15px;">
  <div class="col-md-12">
    <div class="pull-right">
      <input type="text" id="cat_filter" class="form-control input-sm" placeholder="{{ lang._('filter...') }}" style="width:220px;">
    </div>
    <h4>{{ lang._('Categories') }} <small>{{ lang._('used as geosite:NAME in routing rules') }}</small></h4>
    <table class="table table-striped table-condensed" id="grid">
      <thead><tr><th>{{ lang._('Category') }}</th><th>{{ lang._('Domains') }}</th><th>{{ lang._('Reference') }}</th></tr></thead>
      <tbody></tbody>
    </table>
  </div>
</div>

<script>
$(document).ready(function() {
  var api = '/api/xray/geosite';
  var cats = [];

  function esc(s) { return String(s === undefined ? '' : s).replace(/&/g,'&amp;').replace(/</g,'&lt;'); }

  function render(filter) {
    var tb = $('#grid tbody').empty();
    var f = (filter || '').toLowerCase();
    cats.forEach(function(c) {
      if (f && c.name.toLowerCase().indexOf(f) < 0) return;
      var tr = $('<tr>');
      tr.append($('<td>').html('<b>' + esc(c.name) + '</b>'));
      tr.append($('<td>').text(c.domains));
      tr.append($('<td>').html('<code>geosite:' + esc(c.name) + '</code>'));
      tb.append(tr);
    });
  }

  function reload() {
    ajaxCall(api + '/categories', {}, function(data) {
      cats = data.categories || [];
      $('#g_source').text(data.source || '-');
      $('#g_updated').text(data.updated || '-');
      $('#g_count').text(data.count);
      render($('#cat_filter').val());
    });
  }

  $('#cat_filter').on('input', function() { render($(this).val()); });
  $('#btn_refresh').click(function() {
    $('#g_msg').text('{{ lang._('extracting...') }}');
    ajaxCall(api + '/refresh', {}, function(data) {
      $('#g_msg').text(data.result === 'ok' ? '{{ lang._('done') }}: ' + data.count : esc(data.error || 'failed'));
      reload();
    });
  });
  $('#btn_download').click(function() {
    $('#g_msg').text('{{ lang._('downloading...') }}');
    ajaxCall(api + '/update', {geosite: $('#dl_geosite').is(':checked'), geoip: $('#dl_geoip').is(':checked')}, function(data) {
      var parts = [];
      Object.keys(data.files || {}).forEach(function(k){ parts.push(k + ': ' + data.files[k]); });
      $('#g_msg').text(parts.join(' | '));
      reload();
    });
  });
  $('#file_upload').change(function() {
    var file = this.files[0];
    if (!file) return;
    var fd = new FormData();
    fd.append('dat', file);
    $('#g_msg').text('{{ lang._('uploading...') }}');
    $.ajax({url: api + '/upload', type: 'POST', data: fd, processData: false, contentType: false, dataType: 'json',
      success: function(data) {
        $('#g_msg').text(data.result === 'saved' ? '{{ lang._('uploaded') }}: ' + data.size + ' bytes' : esc(data.error || 'failed'));
        reload();
      },
      error: function(xhr) { $('#g_msg').text('upload failed: ' + xhr.status); }
    });
    $(this).val('');
  });

  reload();
});
</script>
