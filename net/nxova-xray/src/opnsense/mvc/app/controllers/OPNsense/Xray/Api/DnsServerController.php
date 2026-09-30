<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

/**
 * CRUD for DNS servers, stored as the nested "servers" list of the
 * singleton dns section (storeName 'dns').
 */
class DnsServerController extends CrudBase
{
    protected $storeName = 'dns';
    protected $listKey = 'servers';

    protected function defaults()
    {
        return array(
            'enabled' => true,
            'address' => '',
            'port' => 53,
            'domains' => array(),
            'expectIPs' => array(),
            'skipFallback' => false,
        );
    }

    protected function validate($item, $isNew)
    {
        $errors = array();
        if (trim(isset($item['address']) ? $item['address'] : '') === '') {
            $errors[] = 'address must not be empty';
        }
        $port = isset($item['port']) ? (int)$item['port'] : 0;
        if ($port < 1 || $port > 65535) {
            $errors[] = 'port must be 1-65535';
        }
        return $errors;
    }
}
