# AnyUsagePin

![macOS 12+](https://img.shields.io/badge/macOS-12%2B-000000?logo=apple&logoColor=white)
![以 Flutter 打造](https://img.shields.io/badge/Built_with-Flutter-02569B?logo=flutter&logoColor=white)
![支援 OMP](https://img.shields.io/badge/Agent-OMP-168575)

[English](README.md) · [繁體中文](README.zh-TW.md)

**把你的 AI 訂閱放進同一個選單列，不必再登入另一套供應商 app。**

AnyUsagePin 是以 Flutter 打造的 macOS 選單列 app，可追蹤程式開發 agent 已授權帳號的剩餘配額、餘額與重置倒數，涵蓋 **Claude（Anthropic）、OpenAI／Codex、Google Antigravity 與其他訂閱**。

**不用交出憑證。** App 不直接從系統或 agent 的憑證儲存區讀取 OAuth access／refresh token 或 API key，不建立自己的供應商 token 儲存庫，也不直接呼叫供應商的配額／模型 API。它讀取的是你已安裝的 agent CLI 所產生的用量報表。

**不用在供應商的本機桌面 app 登入。** 只要帳號已在 agent 授權，且 agent 能提供用量，即使 Claude、Codex 或 Antigravity 的桌面 app 沒有登入，甚至沒有安裝，也能在這裡顯示訂閱。同一供應商的多個帳號也可以一起顯示。

[為什麼選擇這個 app](#為什麼選擇-anyusagepin) · [快速開始](#快速開始) · [自訂顯示](#打造你的選單列) · [支援的 agent](#支援的-agent) · [未來規劃](#未來規劃) · [隱私](#隱私與本機資料) · [參與開發](#開發與貢獻)

## 為什麼選擇 AnyUsagePin

**顯示 agent 能取得用量的訂閱，而不只是桌面 app 當下登入的那個帳號。** AnyUsagePin 使用 agent 回報的帳號與配額，不依賴本機 Claude、Codex 或 Antigravity app 的登入狀態。

已在 **OMP** 授權的帳號，只要 OMP 能提供用量，就不必再登入供應商的本機桌面 app。工作與私人帳號會各自保留，即使是同一供應商的兩個訂閱，也不會混在一起。這**不是匿名查詢任意遠端帳號**：你仍需安裝並登入支援的 agent，且 agent 必須能取得該帳號的配額。

- **憑證留在 agent。** 不需匯入 token／key，不另建供應商登入流程或 app 自有憑證資料庫。認證仍由你原本使用的 agent 管理。
- **以帳號為單位，不取供應商平均值。** 每個帳號及組織／專案範圍都保有自己的配額與身分。
- **釘選你在意的資訊。** 多個訂閱可並排放進同一個選單列項目，每個 pin 最多兩行。不自動選帳號，也不按配額重新排列。
- **文字與進度條自由搭配。** 可將重置倒數條搭配剩餘配額文字，或把配額條搭配倒數文字。兩個顯示通道能選擇不同的計量視窗。
- **選擇適合自己的面板。** 可切換帳號卡片、精簡表格與釘選帳號聚焦模式，並選擇系統／淺色／深色主題與顯示密度。
- **不掩蓋資料的不確定性。** 缺資料、已到重置期限或查詢失敗時，會保留可辨識的提示，不把它們變成令人誤以為正常的零值。
- **資料留在本機。** 沒有 app 自有的供應商 token 儲存庫、雲端帳號或遙測。

## 快速開始

### 安裝 macOS app

**目前版本：[AnyUsagePin 1.1.0](https://github.com/TerryHuangHD/any-usage-pin/releases/tag/v1.1.0)（build 5）。** 此版本加入 B1 Orbit app 圖示、帳號獨立的重置席次與最早到期時間、精確的 10–50 pt pin 進度條長度滑桿，以及整合「選項」操作的精簡雙行面板頁尾。

1. 從 [GitHub Releases](https://github.com/TerryHuangHD/any-usage-pin/releases/latest) 下載 **macOS 通用版 DMG**。若要驗證檢查碼，請將 `appcast.xml` 與 `SHA256SUMS` 一併下載到同一個目錄，再執行 `shasum -a 256 -c SHA256SUMS`。
2. 開啟 DMG，將 **AnyUsagePin.app** 拖進 **Applications（應用程式）**。
3. 從 Applications 開啟 AnyUsagePin。它會出現在選單列，不會出現在 Dock。

需要 **macOS 12.0 以上**，以及**已安裝並完成登入的 OMP**。使用下載的正式版不需要 Flutter 或 Xcode。通用版同時包含 Apple Silicon 與 Intel 執行檔；第一次開啟時，macOS 仍可能顯示一般的下載 app 確認提示。

### 從原始碼建置

- **macOS 12.0 以上。**
- **Flutter 與 Dart 3.12.2 以上的相容 3.x 版本**，以及 Xcode、Flutter macOS 工具鏈。專案已使用 Flutter 3.44.9／Dart 3.12.2 建置。
- **已安裝並登入 OMP**，且版本支援 `omp usage --json`。此 app 已搭配 OMP 18.5.0 驗證。

先確認 OMP 能回報你的用量：

```sh
omp usage --json
```

不使用公司簽署憑證進行本機開發時，請先複製此 repository，再於專案根目錄執行：

```sh
flutter pub get
flutter build macos --debug
open -a "$PWD/build/macos/Build/Products/Debug/AnyUsagePin.app"
```

若要啟動後立即開啟用量面板：

```sh
open -a "$PWD/build/macos/Build/Products/Debug/AnyUsagePin.app" --args --show
```

Release build 使用 **Developer ID Application: LI-SHENG TECHNOLOGY CO., LTD. (V6C4PTHC4J)**，並啟用 Hardened Runtime 與安全簽署時間戳記。已發布的通用版 app 與 DMG 均通過 Apple 公證並附加公證票證；Gatekeeper 將其辨識為 **Notarized Developer ID**。最終 DMG 已實際掛載，並在 Apple Silicon 上執行其中的 app。

macOS bundle identifier 為 `com.terryhuanghd.AnyUsagePin`，定義於 [AppInfo.xcconfig](macos/Runner/Configs/AppInfo.xcconfig)。它與本機資料儲存目錄分開，因此變更 identifier 不會重設既有 pin 或偏好設定。

### 建立第一個 pin

1. 開啟選單列 app，查看 OMP 回報的帳號。
2. 在面板下方開啟 **Options／選項**，選擇 **Settings／設定…**，再進入 **Customize／客製化顯示**，為帳號新增 pin。
3. 分別選擇上／下行文字與進度條使用的計量視窗。
4. 檢查預覽、完成編輯後，按 **Apply／套用** 儲存。

App 沒有 Dock 圖示。所有 pin 依照設定順序並排顯示於同一個選單列項目；點選其中任何位置都會開啟用量面板。沒有 pin 時，同一個項目會顯示 app 啟動圖示。這個精簡面板是唯讀的，呈現各帳號的剩餘配額、進度、重置時間與資料品質警告。固定頁尾的第一行顯示 **AnyUsagePin 與已安裝版本**，第二行顯示查詢進度或下次更新倒數。將游標停在更新資訊上，可查看原始快照時間與更新間隔。**Options／選項** 選單整合手動更新、設定、app 更新狀態／操作與結束。查詢進行中無法重複手動更新。按 Escape、點擊面板外部或切換 app，只會隱藏面板，不會停止背景查詢。

Claude 與 Codex 的 **Reset seats／重置席次** 以單行色彩摘要顯示席次數與最早到期倒數：剩餘 **超過 7 天為綠色**、**7 天以內為橘色**、**3 天以內為紅色**。游標停在摘要上，可查看以本機時區表示的完整最早到期時間，不再用另一行重複顯示日期。已到期席次會保持紅色，顯示 **已到期／待來源更新**，直到 OMP 提供新資料；app 不會自行扣減來源回報的席次數。來源未提供席次數或回報 **0 席次**時，整個摘要會隱藏。席次數大於零但到期時間未知時維持中性色；資料過舊時會在倒數旁標示 **舊資料**。倒數與緊急程度隨面板既有的 30 秒時鐘更新，不必等下一次來源查詢。

Anthropic 帳號若有 OMP 回報的 OAuth 重新登入提醒，會在對應帳號卡片上顯示精簡橘色訊息，例如 **⚠ OAuth · 約6天8時內重新登入**；估計期限已過時則顯示 **⚠ OAuth · 請重新登入**。這與配額重置及 **Reset seats** 分開，不會改變正常配額計量的狀態。目前 OMP 會在七天提醒範圍內輸出這些訊息。因 `omp usage --json` 不包含提醒，app 另外執行 `omp usage --provider anthropic`，並以 email／帳號及組織對應來源帳號。倒數是依 OMP 經過取整的文字推估，**不是 app 讀取 token 的到期時間**；使用快取提醒時會顯示 **舊資料**。成功查詢且沒有對應警告時，提醒會清除。

來源設定、pin 新增／編輯、帳號別名／排序、隱藏計量視窗與顯示客製化，都位於獨立的一般 macOS 設定視窗，可關閉、最小化與調整大小。設定視窗失去焦點時仍會保持開啟；用量面板也可獨立開啟。關閉設定只是隱藏保留的視窗，重新開啟時仍保留尚未套用的編輯。客製化仍需按 **Apply／套用** 儲存，或按 **Cancel／取消** 捨棄變更。可透過頁尾 **Options／選項**、設定，或選單列項目的右鍵選單結束 app。右鍵選單另提供 **Settings…**，在含 Sparkle 的版本中也提供 **Check for Updates…**。

**App behavior／App 行為** 中有兩項設定會立即儲存，不會套用或捨棄來源表單中尚未儲存的編輯：

- **Launch at login／開機自動啟動：** 預設關閉。開關讀取的是系統的實際註冊狀態，而非另一份 JSON 設定。macOS 13 以上使用 `SMAppService.mainApp`；若需使用者批准，設定會顯示待批准狀態，並提供前往系統「登入項目」頁面的按鈕。返回設定視窗時會重新讀取系統狀態。macOS 12 則在 `~/Library/LaunchAgents/com.terryhuanghd.AnyUsagePin.plist` 安裝或移除本 app 的使用者 LaunchAgent。
- **Refresh frequency／Refresh 頻率：** 可選 **1 到 10 分鐘**的整數間隔，預設仍為 **5 分鐘**。重新啟動後保留設定，並立即替換等待中的背景計時器。已進行的查詢會正常完成，再按最新間隔安排下一次查詢。

面板、設定、客製化與編輯器使用一致的中性色系與系統藍色控制項。macOS 26 以上使用原生 `NSGlassEffectView`，較舊版本使用 `NSVisualEffectView` 材質。設定視窗保留標準系統標題列及背景；玻璃內容不會取代原生視窗控制鈕。

**從 Finder 啟動後找不到 OMP？** 請選擇頁尾 **Options／選項 → Settings／設定…**，在來源設定填入完整執行檔路徑。留白時會搜尋 PATH，以及常見的 Bun／Homebrew 安裝位置。顯示的 profile 來自啟動環境中的 `OMP_PROFILE`，預設為 `default`；它是唯讀資訊，不是帳號或工作區切換器。

請避免同時執行 Debug 與 Release，因為兩者共用本機設定。

### App 內更新

自 **1.0.2（build 3）**起，正式版包含 [Sparkle 2](https://sparkle-project.org/) 更新功能。已發布的 1.0.0／1.0.1 不含更新程式，需先手動安裝 1.0.2 或更新版本，才能使用 app 內更新。

App 會在啟動及每次開啟用量面板時查詢更新資訊，並合併重疊查詢。背景檢查不會打斷啟動流程，也不會彈出更新對話框。若有相容、未略過的可安裝更新，頁尾的 app 名稱／版本會變成藍色，**Options／選項** 中會出現 **新版 … 可用／下載更新…**。已安裝版本仍會顯示；將游標停在其上可查看 app 更新狀態。選擇 **下載更新…** 後，會進入 Sparkle 標準的下載、驗證、安裝與重新啟動流程。不啟用自動安裝。

頁尾 **Options／選項** 會區分查詢失敗（**無法確認最新版本**）與沒有可安裝更新（**沒有可安裝的更新**）；後者也包含已略過或與系統不相容的版本，不一定代表正在使用最新版。頁尾 **檢查更新…** 與右鍵選單的 **Check for Updates…** 都是使用者主動操作，可重新發現先前略過的版本。App 會尊重 Sparkle 的自動檢查偏好設定。

固定更新 feed 為 GitHub Pages 上的 [`appcast.xml`](https://terryhuanghd.github.io/any-usage-pin/appcast.xml)，更新檔來自 GitHub Releases。查詢與下載都使用 HTTPS；更新查詢失敗不會影響配額顯示。

## 打造你的選單列

每個 pin 對應**一個帳號**，最多有**兩個可獨立設定的顯示行**。每行有兩個可選通道：

| 通道 | 顯示選項 | 計量視窗選擇 |
| --- | --- | --- |
| 文字 | 剩餘配額、已用配額、重置倒數或關閉 | 該帳號任何可用的計量視窗 |
| 進度條 | 剩餘配額比例、已用配額比例、剩餘時間比例或關閉 | 可獨立選擇，不必與文字相同 |

以下為設定範例，**不是即時用量數值**：

| 目的 | 文字 | 進度條 |
| --- | --- | --- |
| 同時觀察配額與時間 | 五小時剩餘配額 | 五小時重置倒數 |
| 在同一行觀察兩種限制 | 每週剩餘配額 | 五小時重置倒數 |
| 偏好時間標籤 | 五小時重置倒數 | 每週已用配額 |
| 保持極簡 | 關閉 | 剩餘配額比例 |

可以只顯示文字、只顯示進度條，或兩者一起顯示。將兩行都關閉，就成為僅顯示圖示的 pin。供應商圖示、共用色彩、可選標籤與標籤寬度可分別設定，也可拖曳 pin 調整順序。

在 **Customize／客製化顯示 → Panel appearance／面板外觀** 中，**Menu bar pin bar length／選單列 pin 條狀長度** 可透過滑桿調整為 **10 到 50 pt**，每次 1 pt，預設 **25 pt**。這是所有配額／倒數條共用的設定，包含未知資料的空心進度條。預覽會立即反映草稿；按 **Apply／套用** 後才更新選單列。

編輯器的預覽固定在可捲動設定下方。按 **Apply／套用** 前，變更都只存在草稿中。套用會儲存並更新顯示，但不會離開客製化頁面，可繼續編輯或再次套用。**Cancel／取消** 與返回按鈕只會捨棄上次成功套用之後的變更。重設顯示預設值不會重設 CLI 路徑，也不會將帳號登出。

選單列的重置倒數文字與客製化預覽採用**分層精度**：不到 24 小時時顯示 `H:MM`，小時不補前導零（`1:44`、`0:05`）；滿 24 小時時，顯示向下取整的剩餘天數（6 天 14 小時顯示為 `6d`）。分界以實際剩餘時間判斷，因此 23 小時 59 分 59 秒仍顯示 `23:59`，不是 `1d`。尚未到期但不到一分鐘時顯示 `0:00`；實際到期後改成 **待更新**，不會假裝配額已補滿。缺少重置時間時保留 **無重置時間**。帳號面板與 tooltip 保留較完整的倒數文字。配額文字、進度條比例、已儲存的行／視窗選擇，以及原生進度條的 **4 pt 粗細**都不變。

倒數進度條的意義是：

```text
剩餘時間比例 = 距離重置的時間 / 來源回報的計量視窗長度
```

它隨既有的 30 秒時鐘更新。若 OMP 省略重置時間或回傳 `null`，但提供正數視窗長度，代表視窗尚未開始：pin 倒數會顯示完整視窗長度，例如五小時視窗顯示 **5:00**（面板／tooltip 顯示 **5時0分**），並顯示滿格倒數條。在 OMP 回報實際重置時間之前不會自行倒數。面板與 pin 的 tooltip 會標示 **尚未開始計時**；這不代表剩餘配額補滿。缺少或非正數的視窗長度、格式錯誤的重置時間，仍會顯示帶有 `?` 的空心條，而非捏造倒數。正常的文字通道也不能掩蓋另一條缺資料或過舊的進度條；tooltip 會列出各通道的視窗與來源資料時間。

OpenAI Codex 與 Claude 的帳號面板也會顯示 **Reset seats／重置席次**（OMP 回報的可用已儲存重置次數）及 **Soonest expires／最早到期**（可用 credits 中最早的有效到期時間）。到期時間使用 Mac 的本機時區；已兌換及在來源觀測時已到期的 credits 不會計入，來源未提供可選的 credit 狀態時仍可接受。來源回報零席次時，資料值是 **0** 且沒有到期時間（`—`）；缺少或格式錯誤的席次數維持 **無資料**，不會變成零。重置 credits 依帳號隔離，保留自己的觀測時間並隨快取／合併保留；此 app 僅讀取，不會兌換 credits。

App 不設定固定的 pin 數量上限。macOS 會決定合併後的選單列項目是否放得下；空間不足時，過寬的項目可能被隱藏。App 不會自動丟棄、折疊、替換或重排 pin。所有已設定的 pin 仍可在客製化中管理。

官方供應商圖示用來辨識訂閱。自動色彩跟隨選單列外觀，不受 app 淺色／深色主題控制；自動色彩與自訂色彩混用時，每個 pin 仍保留自己的自訂色。

## 支援的 agent

| Agent | 狀態 | 資料來源與邊界 |
| --- | --- | --- |
| **OMP** | 已可使用 | `omp usage --json`；支援多供應商與多帳號，但僅限 OMP 能提供的用量報表 |
| **OpenCode** | 規劃整合 | V2 無 token 帳號清單，加上支援的逐帳號配額橋接；此 app 尚未實作 |
| **Pi** | 規劃研究／整合 | 提供明確帳號清單與逐帳號配額契約的 extension bridge；此 app 尚未實作 |

已搭配此 app 驗證的 OMP 供應商報表包含 **Claude（Anthropic）、OpenAI／Codex、Google Antigravity、Grok 與 Cursor**。App 不透過供應商的桌面 app 發現或認證這些帳號；資料來源是 agent 的用量報表。可用性取決於 OMP 版本、已授權帳號與安裝的用量 adapter，而不是供應商桌面 app 的當下登入狀態。這不保證每種訂閱方案或已授權帳號都能被發現。

**Agent 的本機 token 統計不等於訂閱配額。** App 顯示的是供應商經由 agent 回報的限制，不會從本機 token 消耗推算剩餘額度。Anthropic 直接訂閱與 Antigravity 內的 Claude 共用池是不同來源；API key 支出也不能與訂閱配額混為一談。

### 更新頻率與資料品質

- 按設定的 1–10 分鐘間隔查詢 OMP，預設五分鐘。間隔從前一次查詢結束時計算，即使用量面板與設定視窗都已關閉，仍會背景查詢。同一時間只執行一個查詢。
- 手動更新是一般查詢，不會使 OMP 快取失效，也不會強制要求供應商重新回報。
- 保留每個計量的原始觀測時間。同一計量的重複觀測只會以較新資料取代較舊資料；不會加總獨立視窗或共用配額池。
- 保留百分比、USD、credits、requests 等單位，不會捏造單一總百分比。
- 查詢失敗後保留最後已知資料及其時間／警告。缺少時間、來自未來的時間、至少十分鐘前的資料，以及已到期的重置期限，都會標示。
- 已到重置期限只代表**等待來源更新**，不是配額已補滿的證據。
- 找不到帳號時保留既有 pin 綁定與不可用標記，不會將 pin 自動改綁到另一個帳號。

帳號完整 email 仍會與別名一起顯示。一般配額列可隱藏，但缺資料、過舊及錯誤列仍會顯示，包含聚焦模式中未釘選帳號的問題。

## 未來規劃

以下是方向，不是發布日期承諾。**目前只有 OMP 可用。** 新 adapter 必須先提供真實、可歸屬各帳號的配額，才會成為可用來源。

### 下一步：更多 agent，同樣以帳號為核心

- [ ] **完整發現 OMP 帳號。** 加入無 token 帳號清單橋接，區分「已有登入但沒有用量 adapter」與「沒有該帳號」，並顯示用量不可用，而非直接消失或變成 0%。
- [ ] **整合 OpenCode V2。** 將無 token 帳號清單與支援的逐帳號配額 bridge 結合，例如使用者自行安裝的 `opencode-quota`。`stats --json` 是本機統計，不是剩餘訂閱配額；無介面的 bridge 匯出可能使用快取，必須保留真正的來源時間。
- [ ] **研究 Pi 整合。** 評估能提供穩定多帳號清單與明確配額契約的 extension bridge。認證準備完成不等於有用量 API；不擷取任意 TUI 輸出來拼湊資料。
- [ ] **安全切換 agent。** 快照、pin、別名、排序與配置按 agent 隔離。只輪詢目前選定的來源，盡可能取消上一個來源的查詢，即使 A → B → A 快速切換，也要拒收較晚回來的舊結果。回到某個 agent 時還原其顯示設定，不修改該 agent 的目前供應商／帳號或 profile。切換失敗時不會默默改用另一個 agent。

### 候選顯示功能

最初的產品設計也列出以下討論方向；它們**尚未實作，也不屬於已承諾功能**：

- 可設定的表格欄位與數值精度。
- 供應商／帳號／資源排序及群組、按重置時間排序，以及僅在可比較的資源類型內按剩餘配額排序。
- 倒數之外，同時顯示絕對重置時間。
- 可隱藏整個帳號，但仍保留可見錯誤摘要，不隱藏認證或更新問題。
- 各 agent 獨立的外觀覆寫。

雲端同步、app 自有雲端帳號、用量代理、token／費用歷史分析與通知，都**不在已承諾範圍內**。多 agent 支援不代表跨 agent 合併帳號或切換 profile。

<details>
<summary>整合驗收條件與研究參考</summary>

每個 adapter 都應聲明帳號清單是否完整、能否不改變 agent 目前帳號就查詢每個帳號的配額、資料是即時／快取／匯出，以及哪些供應商或資源不受支援或無法可靠歸屬。

已知登入但沒有配額介面的帳號，應保留並標示不可用。帳號清單不完整時必須明示。不捏造配額、不發送模型探測、不擷取憑證資料庫，也不為蒐集用量而切換帳號。

介面會隨 agent 版本與 extension 不同。研究參考：

- [OMP usage CLI](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/cli/usage-cli.ts)、[帳號篩選](https://github.com/can1357/oh-my-pi/blob/main/packages/coding-agent/src/slash-commands/helpers/usage-accounts.ts)、[用量型別](https://github.com/can1357/oh-my-pi/blob/main/packages/ai/src/usage.ts)，以及 [cache／auth broker](https://github.com/can1357/oh-my-pi/blob/main/docs/auth-broker-gateway.md)。
- [OpenCode V2 帳號](https://opencode.ai/v2/docs/cli/providers/)與 [JSON 帳號清單實作](https://github.com/anomalyco/opencode/blob/v2/packages/cli/src/commands/handlers/auth/list.ts)。研究中的清單介面為 `opencode auth list --format json`。
- [OpenCode quota 外部整合](https://github.com/slkiser/opencode-quota/blob/main/docs/readme/external-integration.md)。其無介面的 `show --json` 讀取快取報表，不保證能取得供應商即時配額。
- [Pi CLI](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/cli.md)。`auth check --json` 回報認證是否準備完成，而非配額。

</details>

## 隱私與本機資料

**憑證由 agent 管理，不由這個 app 管理。** AnyUsagePin 不要求你貼上 token 或 key，不提供供應商登入／登出，不直接從系統／agent 的憑證儲存區讀取 OAuth access／refresh token 或 API key，也不建立自己的供應商 token 儲存庫。不切換 agent 目前的帳號，也不發送模型探測。

| 安全／隱私問題 | 實際行為 |
| --- | --- |
| App 會讀取系統或 agent 的 OAuth token／API key 嗎？ | **不直接存取憑證。** 它讀取 CLI 用量報表，不讀取憑證檔案或資料庫。 |
| App 會直接呼叫供應商配額或模型 API 嗎？ | **不會。** 配額查詢委由已安裝的 agent CLI 處理，app 不實作自己的供應商 API client。 |
| 必須在本機登入 Claude、Codex 或 Antigravity 嗎？ | **不用在桌面 app 登入。** 但支援的 agent 仍需已獲得該帳號授權，而且能回報其用量。 |
| 整個流程完全不會連網嗎？ | **不是。** CLI 可能連線至供應商；app 的更新檢查／下載透過 HTTPS 連線至 GitHub。 |
| App 會上傳帳號身分或配額快照嗎？ | **不會。** 這些資料保留在本機，不會包含在 app 更新請求中。 |

配額查詢使用 `omp usage --json`；Anthropic 重新登入提醒另外使用 `omp usage --provider anthropic`。這些都是固定 CLI 引數，不是插入使用者輸入後交給 shell 執行的字串。App 讀取報表並保留正規化的帳號／配額資料，不會向使用者顯示或持久儲存供應商 stderr。

**CLI 仍負責自己的認證與網路行為。** 它可能使用自己的 OAuth token／API key、刷新 OAuth、呼叫供應商 API，或更新快取／歷史／憑證狀態。執行 CLI **不代表保證零網路請求或零副作用**。此 macOS app 未受 sandbox 限制，子行程也會繼承啟動環境；請使用你信任的已安裝 agent CLI。

App 更新請求透過 HTTPS 連線至 GitHub Pages 與 GitHub Releases，不包含供應商憑證、帳號識別資訊或配額快照。Sparkle 系統概況回報已停用，但代管服務仍會收到一般下載／請求的連線中繼資料。

設定與正規化快照儲存在你的 Mac：

```text
~/Library/Application Support/AnyUsagePin/
  preferences.json
  snapshot-omp.json
```

快照包含**完整 email、帳號／組織識別資訊與配額資料**，但不儲存原始 CLI payload、access token、refresh token、API key 或任意 metadata。公開分享截圖或測試資料前，請先移除敏感資訊。

<details>
<summary>儲存權限、遷移與復原</summary>

資料目錄權限為 `0700`，檔案權限為 `0600`；寫入會依序執行，並以原子方式替換檔案。設定損壞時會回報，不會直接覆寫；使用者明確重設前，會先保留損壞檔案的備份。

**從 Cross Agent Usage 升級：** 啟動 AnyUsagePin 前，請先結束舊 app。若 `Application Support/AnyUsagePin` 尚不存在，第一次儲存操作會將舊的 `Application Support/Cross Agent Usage` 目錄搬到新名稱，保留 pin、別名、偏好設定、快照與復原備份。若新目錄已存在，會以新目錄為準，不合併或覆寫兩者。舊路徑若不是一般目錄，會拒絕遷移，而非跟隨連結或替換它。

App 偏好設定使用 schema v2，正規化用量快照仍使用 schema v1。沒有更新間隔欄位的設定維持預設五分鐘；沒有 pin 條長欄位的設定使用 25 pt。先前 Level 1–4 的條長會遷移成等效的 16、24、32、40 pt。舊版 v1 pin 會在記憶體內遷移，保留原本的文字／配額條配置。原本僅顯示圖示的 pin 不會自動開啟先前隱藏的通道或標籤；舊的重置文字也不會自動多出倒數條。讀取設定不會重寫原檔，下一次使用者更改偏好設定時才會寫入新格式。

正規化快照會保留 OMP 的「尚未開始重置」標記，不捏造重置時間。缺少此標記的舊快取會維持未知重置狀態，直到 OMP 成功更新並提供新的來源語意。

</details>

## 開發與貢獻

[Flutter 層](lib/)負責單一用量 controller、設定／客製化、預覽、輪詢與正規化資料。[Swift／AppKit 層](macos/Runner/)依 controller 的顯示資料渲染包含所有 pin 的單一原生選單列項目與唯讀用量面板，並在獨立且保留的設定視窗中承載同一個 Flutter engine。關閉面板只作用於面板，不會關閉設定視窗。品牌圖示已隨 app 打包，不在執行時從網路下載。

**最初的 app 圖示探索：** 可在本機[比較前四個方向](assets/icon_candidates/index.html)，或查看[淺色](assets/icon_candidates/preview-light.png)／[深色](assets/icon_candidates/preview-dark.png)預覽：A **Quota Pin**、B **Orbit**、C **Stack** 與 D **U-Pin**。每個方向都有 1024×1024 SVG 原始檔，以及 16、32、64、128、256、512、1024 像素的透明 PNG。這些探索素材與預覽不會放進 Flutter bundle。

**macOS app 圖示：B1 Orbit Original。** [SVG 原始檔](assets/icon_candidates/b-orbit.svg)已匯出至原生 [Xcode AppIcon set](macos/Runner/Assets.xcassets/AppIcon.appiconset/)，包含 16、32、64、128、256、512、1024 像素。B1 的分段配額環保留原始 B 設計，相較 B3 的連續漸層環，更直接表達帳號獨立配額。[查看採用版本與 B3 替代設計](assets/icon_candidates/orbit.html)；頁面預設選擇 B1，並提供相對應的 SVG／PNG 下載。已移除淘汰的 B2；切換預覽不會改變原生 app 圖示。也可查看[比較圖](assets/icon_candidates/orbit-comparison.png)、[淺色](assets/icon_candidates/orbit-preview-light.png)或[深色](assets/icon_candidates/orbit-preview-dark.png)圖表。

```sh
flutter analyze
flutter test test/core_test.dart test/controller_test.dart
flutter run -d macos
```

[核心回歸測試](test/core_test.dart)涵蓋帳號／範圍隔離、共用配額池、不同順序的觀測、單位與重置邊界、倒數比例、重置席次／到期篩選、子行程取消／輸出限制、錯誤隱私、本機設定儲存（包含 1／10 分鐘更新邊界與 10／50 pt 條長）、遷移，以及損壞檔案保護，包括無效更新間隔與 pin 條長。[Controller 回歸測試](test/controller_test.dart)確保隱藏的到期、缺資料、錯誤或過舊計量仍會顯示於用量面板，並在聚焦模式提示未釘選帳號的問題。

歡迎針對可重現的問題、顯示改進與真實 agent 整合提交 issue 或 pull request。回報問題時，請提供 macOS、Flutter、agent 版本與重現步驟，**不要附上憑證、私人 email 或未遮蔽的用量資料**。提出 adapter 整合時，請一併提供無 token 帳號清單／逐帳號配額契約，以及未來規劃所列的限制。

### 簽署 DMG 正式版

Release 簽署需要公司的 Developer ID Application 憑證與**私鑰**，存放於已解鎖的 Keychain；發布工具另需 **Python 3.12 以上**。Debug build 維持 ad-hoc 簽署；僅 Debug／Profile 關閉 library validation，讓 Sparkle 隨附的 binary 能正常載入。[Release script](scripts/release_macos.py)會由內而外簽署 Sparkle 的 Autoupdate、Updater app、可選 XPC services 及 framework，保留其 entitlements，再簽署 Flutter frameworks 與 app。它會驗證 Developer ID 身分、安全時間戳記、Hardened Runtime、通用 `arm64`／`x86_64` 執行檔，並拒絕除錯用 entitlements。

只驗證本機簽署與封裝、不送公證時：

```sh
python3 scripts/release_macos.py --prepare-only
```

這會產生檔名明確標示的 `*-unnotarized.dmg`。**不要將它當成正式版發布。**

正式公證版可使用已為 Team `V6C4PTHC4J` 授權的既有 `apptogo-notarytool-profile`：

```sh
python3 scripts/release_macos.py --notary-profile apptogo-notarytool-profile
```

若本機沒有該 profile，請在自己的 Terminal 執行 `xcrun notarytool store-credentials PROFILE_NAME --team-id V6C4PTHC4J` 建立，再以 `--notary-profile` 傳入 release script。命令會詢問 Apple ID 與 app 專用密碼；不要把密碼寫入 repository 或貼進聊天。

也可將既有 App Store Connect API key 存放於本機 Keychain，透過 `xcrun notarytool store-credentials` 設定，再將 profile 名稱傳給 release script。需要指定 Keychain 時，使用 `--keychain /path/to/keychain`。

正式流程會先提交已簽署的 app ZIP，要求 Apple 回覆 **Accepted**，再為 app 附加公證票證並製作可拖曳安裝的 DMG。接著簽署、公證 DMG，附加票證、驗證 app 與 DMG 的票證並檢查 Gatekeeper policy。提交失敗時會保留 Apple 回應與診斷紀錄，不會產生看似可正式發布的檔案。

輸出位於 `build/releases/` 下的獨立目錄：app、DMG、公證回應、`appcast.xml` 與 `SHA256SUMS`。正式流程只會在最終 DMG 完成公證與附加票證後，產生 Ed25519 簽署的 Sparkle enclosure；檢查碼涵蓋 DMG 與 XML。`--prepare-only` 不會產生可公開使用的 appcast。Keychain 憑證與本機診斷檔不可放進 repository。雖包含 Intel 執行檔，目前執行時的 smoke 驗證是在 Apple Silicon 上完成。

### 發布更新 feed

Apple Developer ID 簽署與 Sparkle Ed25519 簽署是不同流程。Sparkle 專用私鑰存放於本機 Keychain，帳號名稱為 **`any-usage-pin`**；repository 只提交 `SUPublicEDKey` 公鑰。可使用 Sparkle 的 `generate_keys --account any-usage-pin -x /private/path/key` 備份／移轉私鑰，並以 `-f /private/path/key` 匯入。換到另一台發布機時，應匯入原有私鑰，而不是重新產生；新私鑰無法與已安裝 app 內的公鑰配對。[固定版本工具 helper](scripts/sparkle_tools.py)會驗證 Sparkle 2.10.0 發行檔的檢查碼，再安裝至 `build/sparkle/2.10.0`。

每次發布穩定版時：

1. 在 `pubspec.yaml` 同時增加顯示版本與 build number。Sparkle 比較的是 `CFBundleVersion`（`+` 後的數字），每次更新都必須增加。
2. 執行上述正式公證 release 命令。
3. 建立 tag 為 `v` 加顯示版本的**草稿 GitHub Release**，從同一個輸出目錄上傳最終的 `AnyUsagePin-VERSION-macos-universal.dmg`、`appcast.xml` 與 `SHA256SUMS`。不要再修改或重新封裝 DMG。
4. 確認三個檔案都已上傳後，才正式發布。

[發布 workflow](.github/workflows/publish-appcast.yml)會在穩定 Release 發布或手動觸發時執行。它會選擇目前最新的穩定版，驗證 metadata、檔案大小、SHA256 檢查碼與 DMG 的 Ed25519 簽章，再將完全相同的 XML 發布到 GitHub Pages。缺少檔案、預覽版或簽章無效時，不會發布損壞的 feed。部署會依序執行；workflow 只使用 `GITHUB_TOKEN`，不使用更新私鑰。

GitHub Pages 的來源必須選擇 **GitHub Actions**。`github-pages` environment 必須允許 `main` 分支與 `v*` **tag** 部署：Release 觸發的 workflow 雖然會從 `main` 取得發布程式碼，但部署仍以該 Release 的 tag 為準。首次發布支援 Sparkle 的版本之前，workflow 必須先存在於 `main`。不需要另外提交 XML 或維護 CI 私鑰 secret。若要在本機使用 OpenSSL 3 驗證已發布版本：

```sh
GH_TOKEN="$(gh auth token)" python3 scripts/publish_appcast.py \
  --repository TerryHuangHD/any-usage-pin --output build/pages
```

App／DMG 的公證及更新流程已在本機實際驗證：隔離的 build-2 app 成功發現、下載、安裝更新，並重新啟動為真正簽署的 build 3。已發布的 1.0.2 檔案通過 GitHub 即時下載、檢查碼與 Ed25519 驗證；[由 Release 觸發的 Actions 部署](https://github.com/TerryHuangHD/any-usage-pin/actions/runs/37147648535)發布了位元組完全相同的公開 feed。未經修改的已公證 1.0.2 app 查詢該 HTTPS feed 後，正確顯示沒有可安裝更新。

### 品牌素材與來源標示

供應商商標仍歸各自權利人所有。使用它們是為了辨識服務，不代表受到供應商背書或有合作關係。向量原始檔位於 [assets/provider_sources/](assets/provider_sources/)，點陣素材位於 [assets/providers/](assets/providers/)。

| 訂閱 | 官方素材來源 |
| --- | --- |
| OpenAI／Codex | [OpenAI 品牌規範](https://openai.com/brand/)與 [logo archive](https://cdn.openai.com/brand/openai-logos.zip)，使用 Blossom 圖示 |
| Claude | 來自[官方 Claude 網站](https://claude.com/)的 Splat 圖示 |
| Cursor | [Cursor 品牌規範](https://cursor.com/brand)與 [brand assets](https://ptht05hbb1ssoooe.public.blob.vercel-storage.com/assets/brand/cursor-brand-assets.zip)，使用 2D Cube 圖示 |
| Grok | 來自[官方 xAI 網站](https://x.ai/)的 Grok 圖示 |
| Antigravity | [官方 Google Antigravity 圖示](https://antigravity.google/assets/image/antigravity-logo.png) |

### 授權

本專案採用 [MIT License](LICENSE)。Copyright (c) 2026 TerryHuangHD。供應商商標與素材仍受各自權利人的權利及適用條款限制。
