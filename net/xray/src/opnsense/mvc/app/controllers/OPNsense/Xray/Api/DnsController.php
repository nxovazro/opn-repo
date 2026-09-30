<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Xray\Store;

/**
 * DNS section (singleton) get/set. The server list itself is managed
 * through DnsServerController.
 */
class DnsController extends ApiControllerBase
{
    public function getAction()
    {
        return array('dns' => Store::load('dns', array()));
    }

    public function setAction()
    {
        $data = $this->request->getJsonRawBody(true);
        if (!is_array($data)) {
            $data = array();
        }
        $item = isset($data['dns']) && is_array($data['dns']) ? $data['dns'] : $data;

        $errors = array();
        $port = isset($item['port']) ? (int)$item['port'] : 53;
        if ($port < 1 || $port > 65535) {
            $errors[] = 'port must be 1-65535';
        }
        $qs = isset($item['queryStrategy']) ? $item['queryStrategy'] : 'UseIP';
        if (!in_array($qs, array('UseIP', 'UseIPv4', 'UseIPv6'))) {
            $errors[] = 'queryStrategy invalid';
        }
        if (!empty($errors)) {
            return array('result' => 'failed', 'validations' => $errors);
        }

        $current = Store::load('dns', array());
        $merged = array_merge($current, $item);
        $merged['enabled'] = !empty($merged['enabled']);
        $merged['disableCache'] = !empty($merged['disableCache']);
        $merged['disableFallback'] = !empty($merged['disableFallback']);
        $merged['port'] = $port;
        // never drop the server list here; it is managed separately
        $merged['servers'] = isset($current['servers']) ? $current['servers'] : array();
        if (!Store::save('dns', $merged)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved');
    }
}
