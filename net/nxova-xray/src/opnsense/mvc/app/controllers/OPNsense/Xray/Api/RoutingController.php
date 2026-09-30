<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Xray\Store;

class RoutingController extends CrudBase
{
    protected $storeName = 'routing';
    protected $listKey = 'rules';

    protected function defaults()
    {
        return array(
            'enabled' => true,
            'priority' => 100,
            'name' => '',
            'type' => 'field',
            'domain' => array(),
            'ip' => array(),
            'port' => '',
            'network' => '',
            'protocol' => array(),
            'inboundTag' => array(),
            'source' => array(),
            'user' => array(),
            'attrs' => array(),
            'outboundTag' => '',
        );
    }

    protected function validate($item, $isNew)
    {
        $errors = array();
        if (!is_numeric(isset($item['priority']) ? $item['priority'] : null)) {
            $errors[] = 'priority must be numeric';
        }
        if (trim(isset($item['outboundTag']) ? $item['outboundTag'] : '') === '') {
            $errors[] = 'outboundTag must be set';
        }
        return $errors;
    }

    protected function sortItems($items)
    {
        // ascending priority; stable for equal priority (keeps UI/config.xml order)
        usort($items, function ($a, $b) {
            $pa = (int)(isset($a['priority']) ? $a['priority'] : 100);
            $pb = (int)(isset($b['priority']) ? $b['priority'] : 100);
            if ($pa === $pb) {
                return 0;
            }
            return $pa < $pb ? -1 : 1;
        });
        return $items;
    }

    /**
     * Swap priority with the neighbour above/below in priority order.
     * POST {"direction": "up"|"down"}
     */
    public function moveAction($uuid)
    {
        $data = $this->readBody();
        $dir = isset($data['direction']) ? $data['direction'] : 'up';
        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        $ordered = $this->sortItems($items);
        $pos = -1;
        foreach ($ordered as $i => $it) {
            if (isset($it['uuid']) && $it['uuid'] === $uuid) {
                $pos = $i;
                break;
            }
        }
        if ($pos < 0) {
            return array('result' => 'not_found');
        }
        $swap = $dir === 'down' ? $pos + 1 : $pos - 1;
        if ($swap < 0 || $swap >= count($ordered)) {
            return array('result' => 'ok', 'note' => 'already at edge');
        }
        // exchange priorities so apply() order follows the UI order
        $tmp = $ordered[$pos]['priority'];
        $ordered[$pos]['priority'] = $ordered[$swap]['priority'];
        $ordered[$swap]['priority'] = $tmp;
        // write back by uuid
        $byUuid = array();
        foreach ($ordered as $it) {
            $byUuid[$it['uuid']] = $it;
        }
        foreach ($items as $i => $it) {
            if (isset($byUuid[$it['uuid']])) {
                $items[$i] = $byUuid[$it['uuid']];
            }
        }
        $store[$this->listKey] = $items;
        if (!Store::save($this->storeName, $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved');
    }

    /**
     * Return distinct outbound tags for the rule editor's target dropdown:
     * manual outbounds + nodes imported from enabled subscriptions
     * (derived caches) + tags already referenced by rules.
     */
    public function targetsAction()
    {
        $tags = array();
        $ob = Store::load('outbounds', array());
        foreach (isset($ob['outbounds']) ? $ob['outbounds'] : array() as $o) {
            if (!empty($o['tag'])) {
                $tags[] = $o['tag'];
            }
        }
        foreach (Store::subscriptionNodeTags() as $t) {
            $tags[] = $t;
        }
        $rt = Store::load($this->storeName, array());
        foreach (isset($rt[$this->listKey]) ? $rt[$this->listKey] : array() as $r) {
            if (!empty($r['outboundTag'])) {
                $tags[] = $r['outboundTag'];
            }
        }
        $tags = array_values(array_unique($tags));
        sort($tags);
        return array('tags' => $tags);
    }
}
