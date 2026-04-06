---
layout: post
title: "Java 日期時間處理教學：Date、Calendar 與 java.time 完整介紹"
description: "本文整理 Java 日期時間處理方式，從舊版 Date、Calendar、SimpleDateFormat，到 Java 8 的 java.time、Instant、LocalDate 與 ZonedDateTime，快速理解各種 API 的差異與適用場景。"
author: Mark_Mew
categories: [Java]
tags: [Java]
keywords: [Java 日期時間, Java Datetime, Java Date Time, java.time, Date, Calendar, SimpleDateFormat, Instant, LocalDate, ZonedDateTime]
date: 2026-4-6
---

身為開發者，大家對「時間處理」這件事應該都不陌生。

但如果你剛好是 Java 開發者，應該特別有感。因為在早期版本裡，光是建立日期、格式化輸出，甚至只是想把時間往後加幾天，都常常寫得又長又彆扭。

所以這篇想做的事情很簡單：把 Java 處理時間的演進重新梳理一遍。從最早期的 `Date`，一路看到後來的 `Calendar`、`SimpleDateFormat`，最後再回到現在大家比較常用的 `java.time`。

## Date

`java.util.Date` 是 1996 年 Java 1.0 發佈時就存在的「元老級」類別。

早期的 `Date` 幾乎什麼都要管，時間儲存要它處理，格式化要它處理，連日期加減也想交給它。

看起來好像很方便，但實際寫起來其實很不舒服。從下面的範例就能感受到，當時的思路幾乎就是「先塞進同一個類別再說」。

```java
import java.util.Date;

public class Java10Example {
    public static void main(String[] args) {
        // 1. 儲存與建立 (Year 從 1900 開始算，Month 從 0 開始算)
        // 假設要設定 1996 年 1 月 23 日 (Java 發布年份)
        Date date = new Date(96, 0, 23); 

        // 2. 格式化 (Java 1.0 只能靠 toString() 或手動拼接)
        // toLocaleString() 會根據系統語系輸出，但格式無法自訂
        System.out.println("1.0 預設格式: " + date.toString());
        System.out.println("1.0 本地化格式: " + date.toLocaleString());
        
        // 手動格式化範例 (非常麻煩)
        String customFormat = (date.getYear() + 1900) + "/" + (date.getMonth() + 1) + "/" + date.getDate();
        System.out.println("手動拼接格式: " + customFormat);

        // 3. 日期加減 (Java 1.0 沒有 plusDays，必須直接操作 setter)
        // 範例：將日期往後推 10 天
        int currentDay = date.getDate();
        date.setDate(currentDay + 10); 
        
        // 範例：增加 2 小時
        date.setHours(date.getHours() + 2);

        System.out.println("加減後的日期: " + date.toLocaleString());

        // 4. 取得時間戳 (1.0 就有的核心方法)
        long timestamp = date.getTime();
        System.out.println("毫秒數 (Timestamp): " + timestamp);
    }
}
```

不過這套設計很快就出現一堆問題，而且是那種你一寫就會開始皺眉的問題：

1. 年份偏移量：
    `new Date(96, 0, 23)` 其實代表的是 1996 年。
    因為它的內部邏輯是 `1900 + 96`。
2. 可變物件：
    像 `date.setDate()` 這種操作，會直接改動原本那個物件。
    如果這個 `date` 同時被其他地方引用，就很容易產生副作用。
    對多執行緒程式來說，這類設計尤其麻煩。
3. 抽象不足：
    加減日期必須先 `get` 出來、手動運算後再 `set` 回去，整體操作非常笨重。
4. 格式化能力薄弱：
    在 `SimpleDateFormat` 出現之前（Java 1.1），開發者幾乎只能自己拼字串。
    再加上年份從 1900 開始算、月份從 0 開始，整體使用體驗相當差。

## Date + Calendar + SimpleDateFormat

因為 Java 1.0 的 `Date` 實在被嫌到不行，官方在 Java 1.1（1997 年）做了大幅調整，於是後來就變成大家很熟悉的「舊版日期三劍客」，而且這一套一路撐到 Java 8 出現前：

- `Date`：用來表示時間，通常也扮演時間資料的載體
- `Calendar`：負責 `Date` 做不到的加減、年/月/日拆解，以及時區相關處理
- `SimpleDateFormat`：負責把 `Date` 格式化成字串，或把字串解析回 `Date`

你可以把這套組合想成分工合作：`Date` 當容器、`Calendar` 當計算器、`SimpleDateFormat` 當格式化工具。

```java
import java.util.Date;
import java.util.Calendar;
import java.text.SimpleDateFormat;

public class Java11Example {
    public static void main(String[] args) throws Exception {
        // 1. 使用 SimpleDateFormat 解析字串 (化妝師)
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
        Date date = sdf.parse("2024-10-01");

        // 2. 轉入 Calendar 進行計算 (計算器)
        Calendar cal = Calendar.getInstance();
        cal.setTime(date);
        
        // 增加 1 個月又 5 天
        cal.add(Calendar.MONTH, 1);
        cal.add(Calendar.DAY_OF_MONTH, 5);

        // 3. 計算完轉回 Date
        Date resultDate = cal.getTime();

        // 4. 再次格式化輸出
        System.out.println("計算結果: " + sdf.format(resultDate));
    }
}
```

跟最早期的 `Date` 比起來，這一組 API 的確進步很多。

像 `Calendar` 會幫你處理月份進位、閏年這些麻煩事，`SimpleDateFormat` 也終於讓日期格式化這件事看起來比較像樣。

但說到底，它還是沒有把問題處理乾淨，尤其下面這兩點很常讓人翻白眼：

1. 月份依然是從 0 到 11，直覺性仍然很差。
2. `Calendar` 和 `SimpleDateFormat` 都不是執行緒安全的，在多執行緒環境下很容易踩雷。

## Java 8 的 java.time

到了 Java 8（2014 年），官方終於推出全新的 `java.time` 套件（JSR-310），這才算真的把 Java 的時間處理拉進現代。

這套 API 之所以好用，關鍵大概就是下面幾件事：

1. 類別職責切得更清楚。
2. 大多數型別都是不可變物件，更安全。
3. 日期、時間、時區、期間計算，都有對應且語意清楚的類別。

其中最常見，也最值得先認識的幾個類別，就是 `Instant`、`LocalDate` 和 `ZonedDateTime`。

### Instant：絕對時間

視角：外太空、物理學家。

定義：從 `1970-01-01 00:00:00 UTC` 開始計算的時間點。

特性：它不屬於任何國家或時區，代表的是全球唯一的絕對時間。如果你要存資料庫、記錄事件發生的時間，或寫 log，通常用它最穩。

```java
import java.time.Instant;
import java.time.Duration;

// 1. 取得目前的 UTC 時間
Instant now = Instant.now(); 

// 2. 與舊版 Date 互相轉換 (橋接神器)
java.util.Date legacyDate = java.util.Date.from(now);
Instant fromLegacy = legacyDate.toInstant();

// 3. 計算時間差
Instant start = Instant.now();
// ... 執行某段程式碼 ...
Instant end = Instant.now();
Duration elapsed = Duration.between(start, end);
System.out.println("執行耗時: " + elapsed.toMillis() + " 毫秒");
```

### LocalDate：純日期

視角：行事曆、農夫。

定義：只有「年-月-日」，不包含時間，也沒有時區。

場景：生日、紀念日、請假日期。這類資料在意的是「哪一天」，而不是「哪一秒」。不管你人在台北還是紐約，生日本身還是那一天。

```java
import java.time.LocalDate;
import java.time.Month;

// 1. 建立日期 (終於不用 0-11 月了，1 就是 1 月！)
LocalDate today = LocalDate.now();
LocalDate birthday = LocalDate.of(1996, Month.JANUARY, 23);

// 2. 日期運算 (語意化極強)
LocalDate nextWeek = today.plusWeeks(1);
LocalDate lastYear = today.minusYears(1);

// 3. 取得資訊
int year = today.getYear();
boolean isLeap = today.isLeapYear(); // 是否為閏年

System.out.println("今天: " + today);
System.out.println("下週: " + nextWeek);
```

### ZonedDateTime：最完整時間

視角：跨國商務人士、航空公司。

定義：包含「年-月-日-時-分-秒」，以及明確的時區（`ZoneId`）。

場景：跨國視訊會議、全球系統排程、航班時間。它知道台北的 10:00 到紐約會變成幾點，省掉以前用 `Calendar` 手動換算時區的痛苦。

```java
import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.time.LocalDateTime;

// 1. 建立特定時區的時間
ZonedDateTime taipeiNow = ZonedDateTime.now(ZoneId.of("Asia/Taipei"));

// 2. 時區轉換 (這在 Calendar 時代非常痛苦，現在一行搞定)
// 將台北時間直接轉換成紐約對應的時間點
ZonedDateTime nyTime = taipeiNow.withZoneSameInstant(ZoneId.of("America/New_York"));

// 3. 輸出包含時區資訊
System.out.println("台北時間: " + taipeiNow);
System.out.println("紐約時間: " + nyTime);
```

除了修掉過去很多設計上的坑，`java.time` 也很務實地保留了和舊 API 溝通的能力。例如 `Instant` 和 `Date` 之間就可以互相轉換，不用一次把舊系統全部打掉重練。

```java
import java.time.Instant;
import java.util.Date;

Instant instant = Instant.now();
// 核心轉換方法
Date date = Date.from(instant);

System.out.println("Instant: " + instant); // 輸出 UTC 時間
System.out.println("Date: " + date);       // 輸出系統預設時區的時間
```

### Duration 與 Period

在日期與時間的計算上，`java.time` 也拆得比較清楚，最常見的就是 `Duration` 和 `Period`。

#### Duration：持續時間

基準：秒、奈秒。

對象：`Instant`、`LocalTime`、`LocalDateTime`。

適合場景：計算程式執行了幾毫秒、兩個時間點相差幾小時。

```java
Instant start = Instant.now();
Instant end = start.plus(Duration.ofHours(5)); // 加 5 小時
long seconds = Duration.between(start, end).getSeconds();
```

#### Period：日期間隔

基準：年、月、日。

對象：`LocalDate`。

適合場景：計算年齡、合約還剩幾個月到期、兩個日期之間差幾天。

```java
LocalDate today = LocalDate.now();
LocalDate nextYear = today.plus(Period.ofYears(1)); // 加 1 年
int months = Period.between(today, nextYear).getMonths();
```

## 快速結論

如果你只想先記住最實用的幾個結論，那大概就是下面這些：

1. 舊系統維護時，難免還是會碰到 `Date`、`Calendar`、`SimpleDateFormat`。
2. 新專案或新功能，優先使用 `java.time`。
3. 只要牽涉時區、跨地區時間，優先思考 `Instant` 或 `ZonedDateTime`。
4. 如果只是單純表示日期，`LocalDate` 通常就夠了。

回頭看 Java 的時間 API，其實就是一段很典型的演進史：一開始把所有責任都丟給 `Date`，後來發現不行，只好再拆成 `Calendar` 和 `SimpleDateFormat`，最後才在 `java.time` 裡把整個概念整理清楚。

所以理解這段歷史，不只是為了知道 Java 以前有多難寫而已。更實際的意義是，當你今天在維護舊系統、或在新專案裡設計時間欄位時，會更知道自己該選哪一種 API，而不是先寫了再後悔。