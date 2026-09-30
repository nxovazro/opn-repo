<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Base\ApiControllerBase;
use OPNsense\Xray\Store;

/**
 * Generic JSON-store CRUD for os-xray sections.
 *
 * Subclasses define:
 *   protected $storeName  (settings|inbounds|outbounds|routing|subscriptions)
 *   protected $listKey    (inbounds|outbounds|rules|subscriptions)
 * and may override validate($item, $isNew) returning array of error strings.
 */
abstract class CrudBase extends ApiControllerBase
{
    protected $storeName = '';
    protected $listKey = '';

    protected function validate($item, $isNew)
    {
        return array();
    }

    protected function defaults()
    {
        return array();
    }

    protected function sortItems($items)
    {
        return $items;
    }

    protected function readBody()
    {
        $data = $this->request->getJsonRawBody(true);
        if (!is_array($data)) {
            $data = $this->request->getPost();
            if (!is_array($data)) {
                $data = array();
            }
        }
        return $data;
    }

    public function listAction()
    {
        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        return array('rows' => array_values($this->sortItems($items)), 'total' => count($items));
    }

    public function getAction($uuid)
    {
        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        $idx = Store::findIndex($items, $uuid);
        if ($idx < 0) {
            return array('result' => 'not_found');
        }
        return array('result' => 'ok', 'item' => $items[$idx]);
    }

    public function addAction()
    {
        $item = array_merge($this->defaults(), $this->readBody());
        $errors = $this->validate($item, true);
        if (!empty($errors)) {
            return array('result' => 'failed', 'validations' => $errors);
        }
        $item['uuid'] = Store::newUuid();
        $store = Store::load($this->storeName, array());
        if (!isset($store[$this->listKey])) {
            $store[$this->listKey] = array();
        }
        $store[$this->listKey][] = $item;
        if (!Store::save($this->storeName, $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved', 'uuid' => $item['uuid']);
    }

    public function setAction($uuid)
    {
        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        $idx = Store::findIndex($items, $uuid);
        if ($idx < 0) {
            return array('result' => 'not_found');
        }
        $item = array_merge($items[$idx], $this->readBody());
        $item['uuid'] = $uuid; // never allow uuid change
        $errors = $this->validate($item, false);
        if (!empty($errors)) {
            return array('result' => 'failed', 'validations' => $errors);
        }
        $store[$this->listKey][$idx] = $item;
        if (!Store::save($this->storeName, $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved', 'uuid' => $uuid);
    }

    public function delAction($uuid)
    {
        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        $idx = Store::findIndex($items, $uuid);
        if ($idx < 0) {
            return array('result' => 'not_found');
        }
        array_splice($store[$this->listKey], $idx, 1);
        if (!Store::save($this->storeName, $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'deleted');
    }

    public function toggleAction($uuid)
    {
        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        $idx = Store::findIndex($items, $uuid);
        if ($idx < 0) {
            return array('result' => 'not_found');
        }
        $cur = !empty($store[$this->listKey][$idx]['enabled']);
        $store[$this->listKey][$idx]['enabled'] = !$cur;
        if (!Store::save($this->storeName, $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved', 'enabled' => !$cur);
    }
}
