<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Xray\Store;

class GeneralController extends ApiControllerBase
{
    public function getAction()
    {
        $defaults = array(
            'enabled' => false,
            'xray_bin' => '/usr/local/bin/xray',
            'confdir' => '/usr/local/etc/xray/conf.d',
            'asset_dir' => '/usr/local/etc/xray',
            'log_level' => 'warning',
            'log_access' => '',
            'log_error' => '',
            'api_listen' => '',
            'geosite_url' => 'https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat',
            'geoip_url' => 'https://github.com/v2fly/geoip/releases/latest/download/geoip.dat',
        );
        return array('general' => array_merge($defaults, Store::load('settings', array())));
    }

    public function setAction()
    {
        $data = $this->request->getJsonRawBody(true);
        if (!is_array($data)) {
            $data = array();
        }
        $item = isset($data['general']) && is_array($data['general']) ? $data['general'] : $data;

        $errors = array();
        if (isset($item['log_level']) && !in_array($item['log_level'], array('debug', 'info', 'warning', 'error', 'none'))) {
            $errors[] = 'log_level invalid';
        }
        foreach (array('xray_bin', 'confdir', 'asset_dir') as $f) {
            if (isset($item[$f]) && trim($item[$f]) === '') {
                $errors[] = $f . ' must not be empty';
            }
        }
        if (!empty($errors)) {
            return array('result' => 'failed', 'validations' => $errors);
        }

        $current = Store::load('settings', array());
        $merged = array_merge($current, $item);
        $merged['enabled'] = !empty($merged['enabled']);
        if (!Store::save('settings', $merged)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved');
    }
}
