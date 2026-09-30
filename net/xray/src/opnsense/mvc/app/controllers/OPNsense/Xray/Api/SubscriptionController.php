<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Core\Backend;

class SubscriptionController extends CrudBase
{
    protected $storeName = 'subscriptions';
    protected $listKey = 'subscriptions';

    protected function defaults()
    {
        return array(
            'enabled' => true,
            'name' => '',
            'url' => '',
            'last_update' => '',
            'count' => 0,
        );
    }

    protected function validate($item, $isNew)
    {
        $errors = array();
        if (trim(isset($item['name']) ? $item['name'] : '') === '') {
            $errors[] = 'name must not be empty';
        }
        $url = isset($item['url']) ? trim($item['url']) : '';
        if ($url === '' || !preg_match('#^https?://#i', $url)) {
            $errors[] = 'url must be http(s)://';
        }
        return $errors;
    }

    /**
     * Trigger subscription import via configd. POST {"uuid": "..."} or empty for all.
     */
    public function updateAction()
    {
        $data = $this->readBody();
        $uuid = isset($data['uuid']) ? trim($data['uuid']) : '';
        $backend = new Backend();
        $response = $backend->configdpRun('xray subscription_update', array($uuid));
        $decoded = json_decode($response, true);
        if (is_array($decoded)) {
            return $decoded;
        }
        return array('result' => 'ok', 'output' => $response);
    }

    /**
     * Remove all outbounds previously imported from a subscription.
     */
    public function purgeAction($uuid)
    {
        $store = \OPNsense\Xray\Store::load('outbounds', array());
        $items = isset($store['outbounds']) ? $store['outbounds'] : array();
        $before = count($items);
        $items = array_values(array_filter($items, function ($o) use ($uuid) {
            return !(isset($o['from_subscription']) && $o['from_subscription'] === $uuid);
        }));
        $store['outbounds'] = $items;
        if (!\OPNsense\Xray\Store::save('outbounds', $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'ok', 'removed' => $before - count($items));
    }
}
