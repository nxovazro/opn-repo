<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray\Api;

use OPNsense\Core\Backend;
use OPNsense\Xray\Store;

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

    /**
     * Import share links (vless://, vmess://, ...) pasted in the UI.
     * POST {"links": "vless://...\nvmess://..."}.
     * Links are parsed by the subscription parser (configd) and added as
     * structured manual outbounds.
     */
    public function importAction()
    {
        $data = $this->readBody();
        $links = isset($data['links']) ? (string)$data['links'] : '';
        if (trim($links) === '') {
            return array('result' => 'failed', 'error' => 'no links provided');
        }
        $tmp = tempnam(sys_get_temp_dir(), 'xray-import-');
        if ($tmp === false) {
            return array('result' => 'failed', 'error' => 'temp file failed');
        }
        file_put_contents($tmp, $links);
        $backend = new Backend();
        $response = $backend->configdpRun('xray parse_links', array($tmp));
        @unlink($tmp);
        $decoded = json_decode($response, true);
        $parsed = (is_array($decoded) && isset($decoded['outbounds'])) ? $decoded['outbounds'] : array();
        if (empty($parsed)) {
            return array('result' => 'failed', 'error' => 'no valid links found');
        }

        $store = Store::load($this->storeName, array());
        $items = isset($store[$this->listKey]) ? $store[$this->listKey] : array();
        $usedTags = array();
        foreach ($items as $it) {
            if (!empty($it['tag'])) {
                $usedTags[$it['tag']] = true;
            }
        }
        $added = 0;
        $skipped = 0;
        foreach ($parsed as $p) {
            if (!is_array($p) || empty($p['protocol'])) {
                $skipped++;
                continue;
            }
            $tag = trim(isset($p['tag']) ? (string)$p['tag'] : '');
            if ($tag === '') {
                $tag = $p['protocol'] . '-imported';
            }
            $base = $tag;
            $n = 2;
            while (isset($usedTags[$tag])) {
                $tag = $base . '-' . $n++;
            }
            $usedTags[$tag] = true;
            $item = array_merge($this->defaults(), array(
                'uuid' => Store::newUuid(),
                'tag' => $tag,
                'protocol' => $p['protocol'],
                'settings' => isset($p['settings']) ? $p['settings'] : array(),
                'streamSettings' => isset($p['streamSettings']) ? $p['streamSettings'] : array(),
            ));
            if ($this->validate($item, true)) {
                $skipped++;
                continue;
            }
            $items[] = $item;
            $added++;
        }
        $store[$this->listKey] = $items;
        if (!Store::save($this->storeName, $store)) {
            return array('result' => 'failed', 'error' => 'write failed');
        }
        return array('result' => 'saved', 'added' => $added, 'skipped' => $skipped);
    }
}
