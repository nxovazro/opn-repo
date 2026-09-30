<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Core\Backend;
use OPNsense\Xray\Store;

class GeositeController extends ApiControllerBase
{
    /**
     * Category names extracted from geosite.dat (from cache, refreshed on demand).
     */
    public function categoriesAction()
    {
        $cache = Store::load('geosite_categories', array());
        $cats = isset($cache['categories']) ? $cache['categories'] : array();
        return array(
            'updated' => isset($cache['updated']) ? $cache['updated'] : '',
            'source' => isset($cache['source']) ? $cache['source'] : '',
            'count' => count($cats),
            'categories' => $cats,
        );
    }

    /**
     * Re-extract categories from the on-disk geosite.dat via configd.
     */
    public function refreshAction()
    {
        $backend = new Backend();
        $response = $backend->configdRun('xray geosite_list');
        $decoded = json_decode($response, true);
        if (is_array($decoded)) {
            return $decoded;
        }
        return array('result' => 'failed', 'output' => $response);
    }

    /**
     * Download geosite.dat (and optionally geoip.dat) from configured URLs.
     * POST {"geosite": true, "geoip": false}
     */
    public function updateAction()
    {
        $data = $this->request->getJsonRawBody(true);
        if (!is_array($data)) {
            $data = array();
        }
        $settings = Store::load('settings', array());
        $assetDir = '/usr/local/etc/xray';
        $jobs = array();
        if (!empty($data['geosite'])) {
            $jobs['geosite.dat'] = isset($settings['geosite_url']) ? $settings['geosite_url'] : '';
        }
        if (!empty($data['geoip'])) {
            $jobs['geoip.dat'] = isset($settings['geoip_url']) ? $settings['geoip_url'] : '';
        }
        $result = array('result' => 'ok', 'files' => array());
        foreach ($jobs as $file => $url) {
            if ($url === '') {
                $result['files'][$file] = 'no url configured';
                continue;
            }
            $dest = $assetDir . '/' . $file;
            $tmp = $dest . '.tmp';
            $cmd = '/usr/local/bin/fetch -q -o ' . escapeshellarg($tmp) . ' ' . escapeshellarg($url)
                . ' && mv ' . escapeshellarg($tmp) . ' ' . escapeshellarg($dest)
                . ' && chmod 644 ' . escapeshellarg($dest);
            exec($cmd . ' 2>&1', $out, $rc);
            $result['files'][$file] = $rc === 0 ? 'ok' : 'failed: ' . implode("\n", $out);
        }
        // refresh category cache if geosite.dat was updated
        if (isset($result['files']['geosite.dat']) && $result['files']['geosite.dat'] === 'ok') {
            $backend = new Backend();
            $backend->configdRun('xray geosite_list');
        }
        return $result;
    }

    /**
     * Accept an uploaded geosite.dat file (multipart form, field name "dat").
     */
    public function uploadAction()
    {
        if (!$this->request->hasFiles()) {
            return array('result' => 'failed', 'error' => 'no file uploaded');
        }
        $settings = Store::load('settings', array());
        $assetDir = '/usr/local/etc/xray';
        foreach ($this->request->getUploadedFiles() as $file) {
            $dest = $assetDir . '/geosite.dat';
            if (!$file->moveTo($dest)) {
                return array('result' => 'failed', 'error' => 'move failed');
            }
            @chmod($dest, 0644);
            $backend = new Backend();
            $backend->configdRun('xray geosite_list');
            return array('result' => 'saved', 'file' => $dest, 'size' => $file->getSize());
        }
        return array('result' => 'failed', 'error' => 'no file uploaded');
    }
}
