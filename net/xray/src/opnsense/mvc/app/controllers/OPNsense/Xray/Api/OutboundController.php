<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

class OutboundController extends CrudBase
{
    protected $storeName = 'outbounds';
    protected $listKey = 'outbounds';

    protected function defaults()
    {
        return array(
            'enabled' => true,
            'tag' => '',
            'protocol' => 'freedom',
            'settings' => array(),
            'streamSettings' => array(),
        );
    }

    protected function validate($item, $isNew)
    {
        $errors = array();
        if (trim(isset($item['tag']) ? $item['tag'] : '') === '') {
            $errors[] = 'tag must not be empty';
        }
        $protos = array('freedom', 'blackhole', 'vless', 'vmess', 'trojan', 'shadowsocks', 'socks', 'http', 'wireguard', 'dns', 'loopback');
        if (!in_array(isset($item['protocol']) ? $item['protocol'] : '', $protos)) {
            $errors[] = 'unsupported protocol';
        }
        return $errors;
    }
}
