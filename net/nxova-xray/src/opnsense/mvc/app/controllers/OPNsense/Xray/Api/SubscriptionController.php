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
     * The importer writes derived node caches to ui/sub/<uuid>.json; this
     * action then refreshes last_update/count on the subscription items.
     */
    public function updateAction()
    {
        $data = $this->readBody();
        $uuid = isset($data['uuid']) ? trim($data['uuid']) : '';
        $backend = new Backend();
        $response = $backend->configdpRun('xray subscription_update', array($uuid));
        $decoded = json_decode($response, true);
        if (is_array($decoded) && isset($decoded['updated']) && is_array($decoded['updated'])) {
            $store = \OPNsense\Xray\Store::load('subscriptions', array());
            $items = isset($store['subscriptions']) ? $store['subscriptions'] : array();
            foreach ($decoded['updated'] as $r) {
                if (!isset($r['uuid'])) {
                    continue;
                }
                foreach ($items as &$it) {
                    if (isset($it['uuid']) && $it['uuid'] === $r['uuid']) {
                        if (empty($r['error'])) {
                            $it['last_update'] = isset($r['updated']) ? $r['updated'] : '';
                            $it['count'] = (int)(isset($r['imported']) ? $r['imported'] : 0);
                        }
                    }
                }
                unset($it);
            }
            $store['subscriptions'] = $items;
            \OPNsense\Xray\Store::save('subscriptions', $store);
        }
        if (is_array($decoded)) {
            return $decoded;
        }
        return array('result' => 'ok', 'output' => $response);
    }

    /**
     * Remove the derived node cache of a subscription.
     */
    public function purgeAction($uuid)
    {
        $purged = \OPNsense\Xray\Store::deleteSubCache($uuid);
        return array('result' => 'ok', 'purged' => (bool)$purged);
    }

    /**
     * Delete a subscription and its derived node cache.
     */
    public function delAction($uuid)
    {
        $result = parent::delAction($uuid);
        if (isset($result['result']) && $result['result'] === 'deleted') {
            \OPNsense\Xray\Store::deleteSubCache($uuid);
        }
        return $result;
    }
}
