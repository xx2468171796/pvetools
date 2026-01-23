# PVETOOLS宸ュ叿浠嬬粛

## 鍥藉唴浣跨敤
```bash
# 涓嬭浇骞惰繍琛屽畨瑁呰剼鏈?wget https://gitee.com/Poker-Face/pvetools/raw/master/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh
```
## 鍥藉
```bash
# 涓嬭浇骞惰繍琛屽畨瑁呰剼鏈?wget https://raw.githubusercontent.com/xx2468171796/pvetools/main/pvetools.sh
chmod +x pvetools.sh
./pvetools.sh
```
# 馃枼锔?PVETools - Proxmox VE 缁煎悎绠＄悊宸ュ叿

<div align="center">

![Version](https://img.shields.io/badge/鐗堟湰-v3.2-blue)
![PVE](https://img.shields.io/badge/PVE-7.x%20%2F%208.x%20%2F%209.x-green)
![License](https://img.shields.io/badge/璁稿彲-MIT-orange)
![Platform](https://img.shields.io/badge/骞冲彴-Linux-lightgrey)

**涓€绔欏紡 Proxmox VE 杩愮淮绠＄悊鑴氭湰**

闆嗘垚 VM/CT 绠＄悊銆丏ocker 閰嶇疆銆佸瓨鍌ㄧ鐞嗐€佺‖鐩樼洿閫氱瓑鍔熻兘

[蹇€熷紑濮媇(#-蹇€熷紑濮? 鈥?[鍔熻兘浠嬬粛](#-鍔熻兘妯″潡) 鈥?[浣跨敤鎸囧崡](USAGE.md) 鈥?[甯歌闂](#-甯歌闂)

</div>

---

## 馃摙 椤圭洰淇℃伅

**浣滆€?*锛氬鐙埗浣? 
**鐢垫姤缇?*锛歔鐐瑰嚮鍔犲叆](https://t.me/+RZMe7fnvvUg1OWJl)  
**鍏煎鐗堟湰**锛歅VE 7.x / 8.x / 9.x

---

## 鉁?鍔熻兘妯″潡

### 馃敼 VM/CT 绠＄悊
| 鍔熻兘 | 璇存槑 |
|------|------|
| 鍗虫椂鎿嶄綔 | 鍚姩銆侀噸鍚€佸叧鏈恒€佸仠姝€佹寕璧?VM/CT |
| 蹇収绠＄悊 | 鍒涘缓蹇収銆佹仮澶嶅揩鐓?|
| 瀹氭椂浠诲姟 | 瀹氭椂閲嶅惎銆佸畾鏃跺垱寤哄揩鐓с€佸畾鏃跺洖婊氬揩鐓?|
| 鎵归噺鎿嶄綔 | 鏀寔澶氫釜 VMID 鎵归噺鎿嶄綔 |

### 馃敼 Docker 閰嶇疆
| 鍔熻兘 | 璇存槑 |
|------|------|
| 瀹夸富鏈洪厤缃?| 閰嶇疆 PVE 瀹夸富鏈烘敮鎸?LXC 杩愯 Docker |
| 瀹瑰櫒閰嶇疆 | 閰嶇疆 LXC 瀹瑰櫒鐨?Docker 杩愯鐜 |
| Docker 瀹夎 | 鍦ㄥ鍣ㄥ唴鑷姩瀹夎 Docker |

### 馃敼 瀛樺偍绠＄悊
| 鍔熻兘 | 璇存槑 |
|------|------|
| LVM-Thin 瀛樺偍 | 灏嗙墿鐞嗙鐩樺垵濮嬪寲涓?LVM-Thin 瀛樺偍 |
| 纭洏鐩撮€?| 灏嗙墿鐞嗙鐩樼洿閫氬埌 QEMU 铏氭嫙鏈?|
| 鐩撮€氱鐞?| 鏌ョ湅銆佸垹闄ゅ凡閰嶇疆鐨勭鐩樼洿閫?|

### 馃敼 绯荤粺宸ュ叿
| 鍔熻兘 | 璇存槑 |
|------|------|
| 蹇嵎鍛戒护 | 瀹夎 `pvetools` 绯荤粺鍛戒护 |
| 绯荤粺淇℃伅 | 鏌ョ湅 PVE 鐗堟湰銆佺郴缁熶俊鎭?|
| 绗笁鏂瑰伐鍏?| Linux 鎹㈡簮銆佺鎶€lion宸ュ叿绠便€丼-UI 闈㈡澘 |

---

## 馃殌 蹇€熷紑濮?
### 涓€閿繍琛岋紙鎺ㄨ崘锛?
```bash
# 涓嬭浇骞惰繍琛?wget -qO pvetools.sh https://raw.githubusercontent.com/YOUR_USERNAME/PVEt/main/pvetools.sh && bash pvetools.sh
```

### 鏈湴瀹夎

```bash
# 1. 涓嬭浇鑴氭湰
wget -O pvetools.sh https://raw.githubusercontent.com/YOUR_USERNAME/PVEt/main/pvetools.sh

# 2. 娣诲姞鎵ц鏉冮檺
chmod +x pvetools.sh

# 3. 杩愯鑴氭湰
./pvetools.sh

# 4. (鍙€? 瀹夎蹇嵎鍛戒护 - 閫夋嫨鑿滃崟 [4] -> [1]
# 涔嬪悗鍙洿鎺ヤ娇鐢?pvetools 鍛戒护
```

### 绯荤粺瑕佹眰

| 椤圭洰 | 瑕佹眰 |
|------|------|
| 鎿嶄綔绯荤粺 | Proxmox VE 7.x / 8.x / 9.x |
| 鏉冮檺 | root 鐢ㄦ埛 |
| 渚濊禆 | 鍩烘湰鏃犱緷璧栵紝LVM 鍔熻兘闇€瑕?`lvm2` 鍖?|

---

## 馃摉 涓昏彍鍗曢瑙?
```
鈺斺晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晽
鈺?                 PVETools v3.2                               鈺?鈺?               Proxmox VE 缁煎悎绠＄悊宸ュ叿                        鈺?鈺氣晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨晲鈺愨暆
  瀛ょ嫭鍒朵綔 | https://t.me/+RZMe7fnvvUg1OWJl

  PVE 鐗堟湰: 8.x  |  鐜: 瀹夸富鏈?
璇烽€夋嫨鍔熻兘妯″潡:

  [1] VM/CT 绠＄悊      - 鍗虫椂鎿嶄綔銆佸揩鐓с€佸畾鏃朵换鍔?  [2] Docker 閰嶇疆     - LXC 瀹瑰櫒 Docker 鏀寔
  [3] 瀛樺偍绠＄悊        - LVM-Thin銆佺‖鐩樼洿閫?  [4] 绯荤粺宸ュ叿        - 蹇嵎鍛戒护銆佹崲婧愩€佺郴缁熶俊鎭?  [5] 甯姪

  [0] 閫€鍑?```

---

## 馃敡 鍛戒护琛岀敤娉?
```bash
# 浜や簰寮忚彍鍗?pvetools

# 鐩存帴瀹夎蹇嵎鍛戒护
pvetools install

# 鏄剧ず甯姪淇℃伅
pvetools -h
pvetools --help

# 鍐呴儴 cron 璋冪敤锛堝畾鏃朵换鍔′娇鐢級
pvetools --cron snap-create <type> <vmid> <prefix> <keep> <days>
pvetools --cron snap-rollback <type> <vmid> latest <prefix>
```

---

## 馃搧 鏂囦欢浣嶇疆

| 绫诲瀷 | 璺緞 |
|------|------|
| 鑴氭湰浣嶇疆 | `/usr/local/bin/pvetools` (瀹夎鍚? |
| 鏃ュ織鏂囦欢 | `/var/log/pvetools.log` |
| 瀹氭椂閲嶅惎 | `/etc/cron.d/pve-auto-restart-<VMID>` |
| 瀹氭椂蹇収 | `/etc/cron.d/pve-auto-snap-<VMID>` |
| 瀹氭椂鍥炴粴 | `/etc/cron.d/pve-auto-rollback-<VMID>` |
| 蹇収璁板綍 | `/var/lib/pve-auto/snaps-<type>-<VMID>.list` |

---

## 鉂?甯歌闂

<details>
<summary><b>Q: 鎻愮ず"璇蜂互 root 韬唤杩愯姝よ剼鏈?</b></summary>

A: 鏈剼鏈渶瑕?root 鏉冮檺杩愯锛岃浣跨敤浠ヤ笅鏂瑰紡锛?```bash
sudo ./pvetools.sh
# 鎴栧垏鎹㈠埌 root 鐢ㄦ埛
su -
./pvetools.sh
```
</details>

<details>
<summary><b>Q: 瀹氭椂浠诲姟娌℃湁鎵ц</b></summary>

A: 妫€鏌?cron 鏈嶅姟鐘舵€侊細
```bash
systemctl status cron
# 鏌ョ湅 cron 鏃ュ織
journalctl -u cron -f
```
</details>

<details>
<summary><b>Q: 蹇収鍒涘缓澶辫触</b></summary>

A: 纭铏氭嫙鏈虹鐩樻敮鎸佸揩鐓у姛鑳斤細
- 鉁?鏀寔锛歓FS銆丩VM-thin銆丆eph RBD銆佹湰鍦扮洰褰?(qcow2)
- 鉂?涓嶆敮鎸侊細LVM銆佹湰鍦扮洰褰?(raw)
</details>

<details>
<summary><b>Q: Docker 閰嶇疆鍚庡鍣ㄦ棤娉曞惎鍔?/b></summary>

A: 纭繚瀹屾垚浠ヤ笅姝ラ锛?1. 閰嶇疆瀹夸富鏈猴紙闇€閲嶅惎 PVE锛?2. 閰嶇疆鐩爣瀹瑰櫒
3. 鍦ㄥ鍣ㄥ唴瀹夎 Docker
</details>

<details>
<summary><b>Q: 纭洏鐩撮€氬悗 VM 鏃犳硶璇嗗埆纾佺洏</b></summary>

A: 妫€鏌ヤ互涓嬪嚑鐐癸細
1. 纭 VM 宸插叧鏈哄啀杩涜鐩撮€氶厤缃?2. 妫€鏌ョ鐩樻槸鍚﹁鍏朵粬 VM 鍗犵敤
3. 灏濊瘯鏇存崲鎺ュ彛绫诲瀷锛圫CSI/SATA/VirtIO锛?</details>

---

## 馃檹 鑷磋阿

鏈伐鍏烽泦鎴愪簡浠ヤ笅浼樼鐨勭涓夋柟宸ュ叿锛?
| 宸ュ叿 | 浣滆€?| 閾炬帴 |
|------|------|------|
| Linux 涓€閿崲婧?| SuperManito | [GitHub](https://github.com/SuperManito/LinuxMirrors) |
| 绉戞妧lion宸ュ叿绠?| kejilion | [GitHub](https://github.com/kejilion/sh) |
| S-UI 闈㈡澘 | alireza0 | [GitHub](https://github.com/alireza0/s-ui) |

---

## 馃摑 鏇存柊鏃ュ織

### v3.2
- 鏂板锛氱郴缁熷伐鍏烽泦鎴愮涓夋柟宸ュ叿
  - Linux 涓€閿崲婧?(SuperManito)
  - 绉戞妧lion宸ュ叿绠?(kejilion)
  - S-UI 闈㈡澘瀹夎 (alireza0)

### v3.1
- 鏂板锛氱‖鐩樼洿閫氬姛鑳?  - 鏀寔灏嗙墿鐞嗙鐩樼洿閫氬埌 QEMU VM
  - 鏀寔 SCSI/SATA/VirtIO 鎺ュ彛绫诲瀷
  - 鏌ョ湅鍜屽垹闄ょ洿閫氶厤缃?
### v3.0
- 閲嶆瀯锛氫笁鍚堜竴缁熶竴鑴氭湰
  - 鏁村悎 VM/CT 绠＄悊銆丏ocker 閰嶇疆銆佸瓨鍌ㄧ鐞?  - 鍏ㄦ柊浜や簰寮忚彍鍗曠晫闈?  - 缁熶竴鐨?Y/N 纭鎿嶄綔
  - 缇庡寲杈撳嚭鏍煎紡

### v2.0
- Docker LXC 閰嶇疆鍔熻兘
- LVM-Thin 瀛樺偍绠＄悊

### v1.0
- 鍒濆鐗堟湰
- 瀹氭椂閲嶅惎銆佸揩鐓х鐞?
---

## 馃摐 璁稿彲璇?
鏈」鐩噰鐢?MIT 璁稿彲璇侊紝璇﹁ [LICENSE](LICENSE) 鏂囦欢銆?
---

## 馃 鍙嶉涓庢敮鎸?
濡傛湁闂鎴栧缓璁紝娆㈣繋锛?
- 馃摦 鎻愪氦 [Issue](https://github.com/YOUR_USERNAME/PVEt/issues)
- 馃挰 鍔犲叆 [鐢垫姤缇(https://t.me/+RZMe7fnvvUg1OWJl) 浜ゆ祦

---

<div align="center">

**猸?濡傛灉瑙夊緱鏈夌敤锛屾杩?Star 鏀寔锛?*

Made with 鉂わ笍 for PVE Users

</div>

---

## 支持作者 / 打赏

如果这个项目对你有帮助，欢迎支持作者继续维护更新（不强制，量力而行）。

![赞赏码](donate_qr.png)

### USDT (TRC20)

- 地址：`TNp2BLnqrsgGPjrABQwvTq6cWyT8iRKk3D`
- 网络：TRC20

![USDT TRC20 QR](usdt_trc20_qr.jpg)

## Support / Donate

If this project helps you, consider supporting the author (optional).

![Donate QR](donate_qr.png)

### USDT (TRC20)

- Address: `TNp2BLnqrsgGPjrABQwvTq6cWyT8iRKk3D`
- Network: TRC20

![USDT TRC20 QR](usdt_trc20_qr.jpg)
