<?php

/*
 * Copyright (C) 2026 os-xray contributors
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED ``AS IS'' AND ANY EXPRESS OR IMPLIED WARRANTIES,
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
 * AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY,
 * OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

namespace OPNsense\Xray;

/**
 * JSON store helper for os-xray.
 *
 * The web UI configuration is kept as plain JSON files under
 * /usr/local/etc/xray/ui/ (one file per section). Writes are atomic
 * (temp file + rename).
 */
class Store
{
    const UI_DIR = '/usr/local/etc/xray/ui';

    private static $files = array(
        'settings' => 'settings.json',
        'inbounds' => 'inbounds.json',
        'outbounds' => 'outbounds.json',
        'routing' => 'routing.json',
        'subscriptions' => 'subscriptions.json',
        'geosite_categories' => 'geosite_categories.json',
    );

    public static function path($name)
    {
        if (!isset(self::$files[$name])) {
            return null;
        }
        return self::UI_DIR . '/' . self::$files[$name];
    }

    public static function load($name, $default = array())
    {
        $path = self::path($name);
        if ($path === null || !is_file($path)) {
            return $default;
        }
        $data = json_decode(@file_get_contents($path), true);
        return is_array($data) ? $data : $default;
    }

    public static function save($name, $data)
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
}
