<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved. (BSD-2-Clause, see LICENSE in plugin root)
 */

namespace OPNsense\Xray;

use OPNsense\Core\Config;

/**
 * Configuration store for os-xray.
 *
 * Backed by the standard OPNsense config.xml (model OPNsense\Xray\Xray,
 * mounted at //OPNsense/xray). The public load()/save() interface keeps
 * the historical array shapes so API controllers are mostly untouched:
 *
 *   settings      -> flat assoc array (general section)
 *   inbounds      -> ['inbounds' => [items]]
 *   outbounds     -> ['outbounds' => [items]]      (manual outbounds only)
 *   routing       -> ['domainStrategy'=>, 'domainMatcher'=>, 'rules'=>[]]
 *   subscriptions -> ['subscriptions' => [items]]
 *   dns           -> flat assoc array + ['servers' => [items]]
 *
 * JSON-ish fields (settings, streamSettings, sniffing, attrs and the
 * string lists domain/ip/protocol/...) are stored as escaped JSON text
 * in config.xml and converted to/from PHP arrays here.
 *
 * Derived data (subscription node caches) lives outside config.xml under
 * UI_DIR/sub/<uuid>.json -- see subCache*() helpers.
 */
class Store
{
    const UI_DIR = '/usr/local/etc/xray/ui';
    const SUB_CACHE_DIR = '/usr/local/etc/xray/ui/sub';

    /* ------------------------------------------------------------------ */
    /* legacy JSON file (only geosite_categories remains file based)       */
    /* ------------------------------------------------------------------ */

    private static $files = array(
        'geosite_categories' => 'geosite_categories.json',
    );

    public static function path($name)
    {
        if (!isset(self::$files[$name])) {
            return null;
        }
        return self::UI_DIR . '/' . self::$files[$name];
    }

    public static function loadJsonFile($name, $default = array())
    {
        $path = self::path($name);
        if ($path === null || !is_file($path)) {
            return $default;
        }
        $data = json_decode(@file_get_contents($path), true);
        return is_array($data) ? $data : $default;
    }

    public static function saveJsonFile($name, $data)
    {
        $path = self::path($name);
        if ($path === null) {
            return false;
        }
        if (!is_dir(self::UI_DIR)) {
            @mkdir(self::UI_DIR, 0750, true);
        }
        $tmp = tempnam(self::UI_DIR, '.tmp-');
        if ($tmp === false) {
            return false;
        }
        file_put_contents($tmp, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT) . "\n");
        @chmod($tmp, 0640);
        return @rename($tmp, $path);
    }

    /* ------------------------------------------------------------------ */
    /* small helpers                                                       */
    /* ------------------------------------------------------------------ */

    public static function newUuid()
    {
        $data = random_bytes(16);
        $data[6] = chr(ord($data[6]) & 0x0f | 0x40);
        $data[8] = chr(ord($data[8]) & 0x3f | 0x80);
        return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($data), 4));
    }

    public static function findIndex($items, $uuid)
    {
        foreach ($items as $i => $item) {
            if (isset($item['uuid']) && $item['uuid'] === $uuid) {
                return $i;
            }
        }
        return -1;
    }

    private static function isUuid($s)
    {
        return is_string($s) && preg_match(
            '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i',
            $s
        ) === 1;
    }

    private static function boolStr($v)
    {
        return !empty($v) ? '1' : '0';
    }

    private static function jsonToArray($text, $default = array())
    {
        if ($text === '' || $text === null) {
            return $default;
        }
        $data = json_decode($text, true);
        return is_array($data) ? $data : $default;
    }

    private static function arrayToJson($value)
    {
        if ($value === null) {
            $value = array();
        }
        if (!is_array($value)) {
            $value = array($value);
        }
        return json_encode($value, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    }

    /* ------------------------------------------------------------------ */
    /* model <-> array conversion                                          */
    /* ------------------------------------------------------------------ */

    private static function generalToArray($model)
    {
        $g = $model->general;
        return array(
            'enabled' => (string)$g->enabled === '1',
            'log_level' => (string)$g->log_level,
            'log_access' => (string)$g->log_access,
            'log_error' => (string)$g->log_error,
            'api_listen' => (string)$g->api_listen,
            'geosite_url' => (string)$g->geosite_url,
            'geoip_url' => (string)$g->geoip_url,
        );
    }

    private static function arrayToGeneral($model, $data)
    {
        $g = $model->general;
        if (array_key_exists('enabled', $data)) {
            $g->enabled = self::boolStr($data['enabled']);
        }
        foreach (array('log_level', 'log_access', 'log_error', 'api_listen', 'geosite_url', 'geoip_url') as $f) {
            if (array_key_exists($f, $data)) {
                $g->$f = (string)$data[$f];
            }
        }
    }

    private static function inboundToArray($uuid, $node)
    {
        return array(
            'uuid' => $uuid,
            'enabled' => (string)$node->enabled === '1',
            'tag' => (string)$node->tag,
            'protocol' => (string)$node->protocol,
            'listen' => (string)$node->listen,
            'port' => (int)(string)$node->port,
            'settings' => self::jsonToArray((string)$node->settings),
            'streamSettings' => self::jsonToArray((string)$node->streamSettings),
            'sniffing' => self::jsonToArray((string)$node->sniffing),
        );
    }

    private static function arrayToInbound($node, $item)
    {
        $node->enabled = self::boolStr(isset($item['enabled']) ? $item['enabled'] : true);
        $node->tag = (string)(isset($item['tag']) ? $item['tag'] : '');
        $node->protocol = (string)(isset($item['protocol']) ? $item['protocol'] : 'dokodemo-door');
        $node->listen = (string)(isset($item['listen']) ? $item['listen'] : '127.0.0.1');
        $node->port = (string)(int)(isset($item['port']) ? $item['port'] : 10808);
        $node->settings = self::arrayToJson(isset($item['settings']) ? $item['settings'] : array());
        $node->streamSettings = self::arrayToJson(isset($item['streamSettings']) ? $item['streamSettings'] : array());
        $node->sniffing = self::arrayToJson(isset($item['sniffing']) ? $item['sniffing'] : array());
    }

    private static function outboundToArray($uuid, $node)
    {
        return array(
            'uuid' => $uuid,
            'enabled' => (string)$node->enabled === '1',
            'tag' => (string)$node->tag,
            'protocol' => (string)$node->protocol,
            'settings' => self::jsonToArray((string)$node->settings),
            'streamSettings' => self::jsonToArray((string)$node->streamSettings),
        );
    }

    private static function arrayToOutbound($node, $item)
    {
        $node->enabled = self::boolStr(isset($item['enabled']) ? $item['enabled'] : true);
        $node->tag = (string)(isset($item['tag']) ? $item['tag'] : '');
        $node->protocol = (string)(isset($item['protocol']) ? $item['protocol'] : 'freedom');
        $node->settings = self::arrayToJson(isset($item['settings']) ? $item['settings'] : array());
        $node->streamSettings = self::arrayToJson(isset($item['streamSettings']) ? $item['streamSettings'] : array());
    }

    private static function subscriptionToArray($uuid, $node)
    {
        return array(
            'uuid' => $uuid,
            'enabled' => (string)$node->enabled === '1',
            'name' => (string)$node->name,
            'url' => (string)$node->url,
            'last_update' => (string)$node->last_update,
            'count' => (int)(string)$node->count,
        );
    }

    private static function arrayToSubscription($node, $item)
    {
        $node->enabled = self::boolStr(isset($item['enabled']) ? $item['enabled'] : true);
        $node->name = (string)(isset($item['name']) ? $item['name'] : '');
        $node->url = (string)(isset($item['url']) ? $item['url'] : '');
        $node->last_update = (string)(isset($item['last_update']) ? $item['last_update'] : '');
        $node->count = (string)(int)(isset($item['count']) ? $item['count'] : 0);
    }

    private static function ruleToArray($uuid, $node)
    {
        return array(
            'uuid' => $uuid,
            'enabled' => (string)$node->enabled === '1',
            'priority' => (int)(string)$node->priority,
            'name' => (string)$node->name,
            'type' => (string)$node->type,
            'domain' => self::jsonToArray((string)$node->domain),
            'ip' => self::jsonToArray((string)$node->ip),
            'port' => (string)$node->port,
            'network' => (string)$node->network,
            'protocol' => self::jsonToArray((string)$node->protocol),
            'inboundTag' => self::jsonToArray((string)$node->inboundTag),
            'source' => self::jsonToArray((string)$node->source),
            'user' => self::jsonToArray((string)$node->user),
            'attrs' => self::jsonToArray((string)$node->attrs),
            'outboundTag' => (string)$node->outboundTag,
        );
    }

    private static function arrayToRule($node, $item)
    {
        $node->enabled = self::boolStr(isset($item['enabled']) ? $item['enabled'] : true);
        $node->priority = (string)(int)(isset($item['priority']) ? $item['priority'] : 100);
        $node->name = (string)(isset($item['name']) ? $item['name'] : '');
        $node->type = (string)(isset($item['type']) ? $item['type'] : 'field');
        foreach (array('domain', 'ip', 'protocol', 'inboundTag', 'source', 'user') as $f) {
            $vals = isset($item[$f]) ? $item[$f] : array();
            if (!is_array($vals)) {
                $vals = array($vals);
            }
            $node->$f = self::arrayToJson(array_values(array_filter(array_map('strval', $vals), function ($v) {
                return $v !== '';
            })));
        }
        $node->port = (string)(isset($item['port']) ? $item['port'] : '');
        $node->network = (string)(isset($item['network']) ? $item['network'] : '');
        $node->attrs = self::arrayToJson(isset($item['attrs']) ? $item['attrs'] : array());
        $node->outboundTag = (string)(isset($item['outboundTag']) ? $item['outboundTag'] : '');
    }

    private static function dnsToArray($model)
    {
        $d = $model->dns;
        $servers = array();
        foreach ($d->servers->server->iterateItems() as $uuid => $node) {
            if ($node->getInternalIsVirtual()) {
                continue;
            }
            $uuid = (string)$uuid;
            $servers[] = array(
                'uuid' => $uuid,
                'enabled' => (string)$node->enabled === '1',
                'address' => (string)$node->address,
                'port' => (int)(string)$node->port,
                'domains' => self::jsonToArray((string)$node->domains),
                'expectIPs' => self::jsonToArray((string)$node->expectIPs),
                'skipFallback' => (string)$node->skipFallback === '1',
            );
        }
        return array(
            'enabled' => (string)$d->enabled === '1',
            'listen' => (string)$d->listen,
            'port' => (int)(string)$d->port,
            'queryStrategy' => (string)$d->queryStrategy,
            'disableCache' => (string)$d->disableCache === '1',
            'disableFallback' => (string)$d->disableFallback === '1',
            'clientIp' => (string)$d->clientIp,
            'servers' => $servers,
        );
    }

    private static function arrayToDns($model, $data)
    {
        $d = $model->dns;
        if (array_key_exists('enabled', $data)) {
            $d->enabled = self::boolStr($data['enabled']);
        }
        if (array_key_exists('listen', $data)) {
            $d->listen = (string)$data['listen'];
        }
        if (array_key_exists('port', $data)) {
            $d->port = (string)(int)$data['port'];
        }
        if (array_key_exists('queryStrategy', $data)) {
            $d->queryStrategy = (string)$data['queryStrategy'];
        }
        foreach (array('disableCache', 'disableFallback') as $f) {
            if (array_key_exists($f, $data)) {
                $d->$f = self::boolStr($data[$f]);
            }
        }
        if (array_key_exists('clientIp', $data)) {
            $d->clientIp = (string)$data['clientIp'];
        }
        if (isset($data['servers']) && is_array($data['servers'])) {
            self::saveItemList($d->servers->server, $data['servers'], 'server');
        }
    }

    private static function serverToArray($uuid, $node)
    {
        return array(
            'uuid' => $uuid,
            'enabled' => (string)$node->enabled === '1',
            'address' => (string)$node->address,
            'port' => (int)(string)$node->port,
            'domains' => self::jsonToArray((string)$node->domains),
            'expectIPs' => self::jsonToArray((string)$node->expectIPs),
            'skipFallback' => (string)$node->skipFallback === '1',
        );
    }

    private static function arrayToServer($node, $item)
    {
        $node->enabled = self::boolStr(isset($item['enabled']) ? $item['enabled'] : true);
        $node->address = (string)(isset($item['address']) ? $item['address'] : '');
        $node->port = (string)(int)(isset($item['port']) ? $item['port'] : 53);
        foreach (array('domains', 'expectIPs') as $f) {
            $vals = isset($item[$f]) ? $item[$f] : array();
            if (!is_array($vals)) {
                $vals = array($vals);
            }
            $node->$f = self::arrayToJson(array_values(array_filter(array_map('strval', $vals), function ($v) {
                return $v !== '';
            })));
        }
        $node->skipFallback = self::boolStr(isset($item['skipFallback']) ? $item['skipFallback'] : false);
    }

    /**
     * Rebuild an ArrayField's items from a plain array, preserving uuids.
     */
    private static function saveItemList($arrField, $items, $kind)
    {
        $uuids = array();
        foreach ($arrField->iterateItems() as $u => $node) {
            if ($node->getInternalIsVirtual()) {
                continue;
            }
            $uuids[] = (string)$u;
        }
        foreach ($uuids as $u) {
            $arrField->del($u);
        }
        if (!is_array($items)) {
            return;
        }
        foreach ($items as $item) {
            if (!is_array($item)) {
                continue;
            }
            $uuid = isset($item['uuid']) && self::isUuid($item['uuid']) ? $item['uuid'] : null;
            $node = $arrField->add($uuid);
            switch ($kind) {
                case 'inbound':
                    self::arrayToInbound($node, $item);
                    break;
                case 'outbound':
                    self::arrayToOutbound($node, $item);
                    break;
                case 'subscription':
                    self::arrayToSubscription($node, $item);
                    break;
                case 'rule':
                    self::arrayToRule($node, $item);
                    break;
                case 'server':
                    self::arrayToServer($node, $item);
                    break;
            }
        }
    }

    private static function loadItemList($arrField, $kind)
    {
        $out = array();
        foreach ($arrField->iterateItems() as $uuid => $node) {
            if ($node->getInternalIsVirtual()) {
                continue;
            }
            $uuid = (string)$uuid;
            switch ($kind) {
                case 'inbound':
                    $out[] = self::inboundToArray($uuid, $node);
                    break;
                case 'outbound':
                    $out[] = self::outboundToArray($uuid, $node);
                    break;
                case 'subscription':
                    $out[] = self::subscriptionToArray($uuid, $node);
                    break;
                case 'rule':
                    $out[] = self::ruleToArray($uuid, $node);
                    break;
                case 'server':
                    $out[] = self::serverToArray($uuid, $node);
                    break;
            }
        }
        return $out;
    }

    /* ------------------------------------------------------------------ */
    /* public load/save                                                    */
    /* ------------------------------------------------------------------ */

    public static function load($name, $default = array())
    {
        if ($name === 'geosite_categories') {
            return self::loadJsonFile($name, $default);
        }
        try {
            $model = new Xray();
            switch ($name) {
                case 'settings':
                    return self::generalToArray($model);
                case 'inbounds':
                    return array('inbounds' => self::loadItemList($model->inbounds->inbound, 'inbound'));
                case 'outbounds':
                    return array('outbounds' => self::loadItemList($model->outbounds->outbound, 'outbound'));
                case 'subscriptions':
                    return array('subscriptions' => self::loadItemList($model->subscriptions->subscription, 'subscription'));
                case 'routing':
                    return array(
                        'domainStrategy' => (string)$model->routing->domainStrategy,
                        'domainMatcher' => (string)$model->routing->domainMatcher,
                        'rules' => self::loadItemList($model->routing->rules->rule, 'rule'),
                    );
                case 'dns':
                    return self::dnsToArray($model);
                default:
                    return $default;
            }
        } catch (\Exception $e) {
            return $default;
        }
    }

    public static function save($name, $data)
    {
        if ($name === 'geosite_categories') {
            return self::saveJsonFile($name, $data);
        }
        if (!is_array($data)) {
            return false;
        }
        try {
            $model = new Xray();
            switch ($name) {
                case 'settings':
                    self::arrayToGeneral($model, $data);
                    break;
                case 'inbounds':
                    self::saveItemList(
                        $model->inbounds->inbound,
                        isset($data['inbounds']) ? $data['inbounds'] : array(),
                        'inbound'
                    );
                    break;
                case 'outbounds':
                    self::saveItemList(
                        $model->outbounds->outbound,
                        isset($data['outbounds']) ? $data['outbounds'] : array(),
                        'outbound'
                    );
                    break;
                case 'subscriptions':
                    self::saveItemList(
                        $model->subscriptions->subscription,
                        isset($data['subscriptions']) ? $data['subscriptions'] : array(),
                        'subscription'
                    );
                    break;
                case 'routing':
                    $r = $model->routing;
                    if (array_key_exists('domainStrategy', $data)) {
                        $r->domainStrategy = (string)$data['domainStrategy'];
                    }
                    if (array_key_exists('domainMatcher', $data)) {
                        $r->domainMatcher = (string)$data['domainMatcher'];
                    }
                    self::saveItemList(
                        $r->rules->rule,
                        isset($data['rules']) ? $data['rules'] : array(),
                        'rule'
                    );
                    break;
                case 'dns':
                    self::arrayToDns($model, $data);
                    break;
                default:
                    return false;
            }
            $model->serializeToConfig();
            Config::getInstance()->save();
            return true;
        } catch (\Exception $e) {
            return false;
        }
    }

    /* ------------------------------------------------------------------ */
    /* subscription derived-data cache: UI_DIR/sub/<uuid>.json             */
    /* ------------------------------------------------------------------ */

    public static function subCachePath($uuid)
    {
        if (!self::isUuid($uuid)) {
            return null;
        }
        return self::SUB_CACHE_DIR . '/' . $uuid . '.json';
    }

    public static function loadSubCache($uuid)
    {
        $path = self::subCachePath($uuid);
        if ($path === null || !is_file($path)) {
            return array();
        }
        $data = json_decode(@file_get_contents($path), true);
        return is_array($data) ? $data : array();
    }

    public static function saveSubCache($uuid, $data)
    {
        $path = self::subCachePath($uuid);
        if ($path === null) {
            return false;
        }
        if (!is_dir(self::SUB_CACHE_DIR)) {
            @mkdir(self::SUB_CACHE_DIR, 0750, true);
        }
        $tmp = tempnam(self::SUB_CACHE_DIR, '.tmp-');
        if ($tmp === false) {
            return false;
        }
        file_put_contents($tmp, json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES) . "\n");
        @chmod($tmp, 0640);
        return @rename($tmp, $path);
    }

    public static function deleteSubCache($uuid)
    {
        $path = self::subCachePath($uuid);
        if ($path === null || !is_file($path)) {
            return false;
        }
        return @unlink($path);
    }

    /**
     * Distinct tags of nodes imported from currently enabled subscriptions.
     * Used to offer subscription nodes in the routing target dropdown.
     */
    public static function subscriptionNodeTags()
    {
        $tags = array();
        $subs = self::load('subscriptions', array());
        $items = isset($subs['subscriptions']) ? $subs['subscriptions'] : array();
        foreach ($items as $sub) {
            if (empty($sub['enabled']) || empty($sub['uuid'])) {
                continue;
            }
            $cache = self::loadSubCache($sub['uuid']);
            foreach (isset($cache['outbounds']) ? $cache['outbounds'] : array() as $ob) {
                if (!empty($ob['tag'])) {
                    $tags[] = $ob['tag'];
                }
            }
        }
        return array_values(array_unique($tags));
    }
}
