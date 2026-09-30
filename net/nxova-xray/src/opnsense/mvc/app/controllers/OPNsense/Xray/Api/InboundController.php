<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

class InboundController extends CrudBase
{
    protected $storeName = 'inbounds';
    protected $listKey = 'inbounds';

    protected function defaults()
    {
        return array(
            'enabled' => true,
            'tag' => '',
            'protocol' => 'dokodemo-door',
            'listen' => '127.0.0.1',
            'port' => 10808,
            'settings' => array(),
            'streamSettings' => array(),
            'sniffing' => array('enabled' => false, 'destOverride' => array('http', 'tls')),
        );
    }

    protected function validate($item, $isNew)
    {
        $errors = array();
        if (trim(isset($item['tag']) ? $item['tag'] : '') === '') {
            $errors[] = 'tag must not be empty';
        }
        $port = isset($item['port']) ? (int)$item['port'] : 0;
        if ($port < 1 || $port > 65535) {
            $errors[] = 'port must be 1-65535';
        }
        $protos = array('dokodemo-door', 'socks', 'http', 'vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard');
        if (!in_array(isset($item['protocol']) ? $item['protocol'] : '', $protos)) {
            $errors[] = 'unsupported protocol';
        }
        return $errors;
    }
}
