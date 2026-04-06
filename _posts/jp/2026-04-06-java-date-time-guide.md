---
layout: post
title: "Javaの日付・時刻処理ガイド: Date、Calendar、java.time をまとめて解説"
description: "Javaの日付・時刻処理を整理して解説します。旧来の Date、Calendar、SimpleDateFormat から、Java 8 の java.time、Instant、LocalDate、ZonedDateTime まで、使い分けのポイントをまとめました。"
author: Mark_Mew
categories: [Java]
tags: [Java]
keywords: [Java 日付 時刻, Java datetime, java.time, Date, Calendar, SimpleDateFormat, Instant, LocalDate, ZonedDateTime]
date: 2026-4-6
---

開発をしていると、日付や時刻の扱いは避けて通れません。

ただ、Java を触っていると、この分野は特に面倒だと感じる場面が多いと思います。古いバージョンでは、日付を作るだけでも、表示形式を整えるだけでも、妙に回りくどいコードになりがちでした。

この記事では、Java の日付・時刻 API がどう変わってきたのかを順番に見ていきます。最初の `Date` から、`Calendar` と `SimpleDateFormat` を経て、現在の `java.time` までをまとめて整理します。

## Date

`java.util.Date` は、1996 年に公開された Java 1.0 の時代から存在するクラスです。

当時の `Date` は、とにかく何でも 1 つで面倒を見ようとしていました。時刻の保持だけでなく、表示や日付の計算まで同じクラスで扱おうとしていたわけです。

一見すると便利そうですが、実際に書いてみると扱いづらさが目立ちます。下の例を見ると、その空気感がよく分かります。

```java
import java.util.Date;

public class Java10Example {
    public static void main(String[] args) {
        // 1. 日付の生成と保持 (Year は 1900 起点、Month は 0 起点)
        // 例: 1996-01-23 (Java が公開された年)
        Date date = new Date(96, 0, 23);

        // 2. フォーマット (Java 1.0 では toString() か手作業が中心)
        // toLocaleString() はシステムロケール依存で、書式は細かく制御できない
        System.out.println("1.0 default format: " + date.toString());
        System.out.println("1.0 localized format: " + date.toLocaleString());

        // 手作業でのフォーマット例
        String customFormat = (date.getYear() + 1900) + "/" + (date.getMonth() + 1) + "/" + date.getDate();
        System.out.println("Manually formatted: " + customFormat);

        // 3. 日付計算 (Java 1.0 には plusDays のような API はない)
        int currentDay = date.getDate();
        date.setDate(currentDay + 10);

        // 2 時間加算
        date.setHours(date.getHours() + 2);

        System.out.println("Updated date: " + date.toLocaleString());

        // 4. タイムスタンプ取得
        long timestamp = date.getTime();
        System.out.println("Timestamp in milliseconds: " + timestamp);
    }
}
```

当然ながら、この設計にはすぐに不満が集まりました。

1. 年の扱いが分かりにくい:
   `new Date(96, 0, 23)` は 96 年ではなく 1996 年を意味します。
   内部では `1900 + 96` として解釈されます。
2. 可変オブジェクトである:
   `date.setDate()` のようなメソッドは元のインスタンスを書き換えます。
   共有しているオブジェクトだと副作用が起きやすくなります。
3. 抽象化が弱い:
   日付を足したいだけでも、値を取り出して自前で計算し、また戻す必要がありました。
4. フォーマット機能が弱い:
   Java 1.1 で `SimpleDateFormat` が入る前は、文字列を手で組み立てる場面も珍しくありませんでした。

## Date + Calendar + SimpleDateFormat

Java 1.0 の `Date` があまりにも使いづらかったため、Java 1.1 では役割を分ける形に見直されました。ここからしばらくの間、Java の日付処理は次の 3 つが中心になります。

- `Date`: 時刻そのものを表すための入れ物
- `Calendar`: 加算・減算や年月日の取得、タイムゾーン処理を担当
- `SimpleDateFormat`: 文字列との相互変換を担当

役割分担としては以前よりずっとましですが、現代的な API と比べるとまだ古さが残ります。

```java
import java.util.Date;
import java.util.Calendar;
import java.text.SimpleDateFormat;

public class Java11Example {
    public static void main(String[] args) throws Exception {
        // 1. SimpleDateFormat で文字列を解析
        SimpleDateFormat sdf = new SimpleDateFormat("yyyy-MM-dd");
        Date date = sdf.parse("2024-10-01");

        // 2. Calendar で計算
        Calendar cal = Calendar.getInstance();
        cal.setTime(date);

        // 1 か月と 5 日を加算
        cal.add(Calendar.MONTH, 1);
        cal.add(Calendar.DAY_OF_MONTH, 5);

        // 3. Date に戻す
        Date resultDate = cal.getTime();

        // 4. もう一度文字列化
        System.out.println("Result: " + sdf.format(resultDate));
    }
}
```

`Calendar` がうるう年や月またぎを吸収してくれるようになり、`SimpleDateFormat` で書式指定もできるようになったのは大きな前進でした。

ただし、実務では次のような不満が残り続けました。

1. 月が相変わらず 0 始まりで直感的ではない。
2. `Calendar` と `SimpleDateFormat` はスレッドセーフではない。

## Java 8 の java.time

Java 8 で導入された `java.time` によって、ようやく Java の日付・時刻処理はかなり使いやすくなりました。

この API が評価されている理由は、主に次の通りです。

1. クラスごとの責務が明確になった。
2. 多くの型がイミュータブルで、安全に扱いやすい。
3. 日付、時刻、タイムゾーン、期間が別々の概念として整理された。

まず押さえておきたいのは `Instant`、`LocalDate`、`ZonedDateTime` の 3 つです。

### Instant: 絶対的な時刻

`Instant` は UTC を基準にした、ある 1 点の時刻を表します。

`1970-01-01 00:00:00 UTC` からの時間として扱われるため、タイムゾーンに依存しない絶対的な値として扱えます。

ログの記録時刻や DB への保存など、時刻のズレを避けたい場面で使いやすい型です。

```java
import java.time.Instant;
import java.time.Duration;

// 1. 現在の UTC 時刻を取得
Instant now = Instant.now();

// 2. 旧 Date API と相互変換
java.util.Date legacyDate = java.util.Date.from(now);
Instant fromLegacy = legacyDate.toInstant();

// 3. 経過時間を計測
Instant start = Instant.now();
// ... run some code ...
Instant end = Instant.now();
Duration elapsed = Duration.between(start, end);
System.out.println("Elapsed time: " + elapsed.toMillis() + " ms");
```

### LocalDate: 日付だけを扱う

`LocalDate` は年・月・日だけを持ち、時刻もタイムゾーンも持ちません。

誕生日、記念日、休暇日など、「何日の出来事か」が重要なケースに向いています。

```java
import java.time.LocalDate;
import java.time.Month;

// 1. 日付を作成 (月が 1 始まりで分かりやすい)
LocalDate today = LocalDate.now();
LocalDate birthday = LocalDate.of(1996, Month.JANUARY, 23);

// 2. 日付計算
LocalDate nextWeek = today.plusWeeks(1);
LocalDate lastYear = today.minusYears(1);

// 3. 情報を取得
int year = today.getYear();
boolean isLeap = today.isLeapYear();

System.out.println("Today: " + today);
System.out.println("Next week: " + nextWeek);
```

### ZonedDateTime: タイムゾーン込みで扱う

`ZonedDateTime` は、日付と時刻に加えて明示的な `ZoneId` を持つ型です。

海外との会議、複数リージョンで動くシステム、国をまたぐスケジュール処理など、タイムゾーンを無視できない場面で活躍します。

```java
import java.time.ZonedDateTime;
import java.time.ZoneId;
import java.time.LocalDateTime;

// 1. 特定タイムゾーンの現在時刻を作成
ZonedDateTime taipeiNow = ZonedDateTime.now(ZoneId.of("Asia/Taipei"));

// 2. 同じ瞬間をニューヨーク時間に変換
ZonedDateTime nyTime = taipeiNow.withZoneSameInstant(ZoneId.of("America/New_York"));

// 3. タイムゾーン込みで出力
System.out.println("Taipei time: " + taipeiNow);
System.out.println("New York time: " + nyTime);
```

`java.time` の良いところは、旧 API と完全に断絶していない点です。たとえば `Instant` と `Date` は相互変換できるので、既存コードと付き合わせながら徐々に移行できます。

```java
import java.time.Instant;
import java.util.Date;

Instant instant = Instant.now();
Date date = Date.from(instant);

System.out.println("Instant: " + instant);
System.out.println("Date: " + date);
```

### Duration と Period

`java.time` では、時間ベースの差分と日付ベースの差分も分けて扱います。

#### Duration: 時間の長さ

`Duration` は秒やナノ秒を基準にした期間です。

`Instant`、`LocalTime`、`LocalDateTime` などと組み合わせて、経過時間や何時間差があるかを扱うときに向いています。

```java
Instant start = Instant.now();
Instant end = start.plus(Duration.ofHours(5));
long seconds = Duration.between(start, end).getSeconds();
```

#### Period: 日付の差分

`Period` は年・月・日を基準にした差分です。

`LocalDate` と相性がよく、年齢計算や契約満了日までの残り期間を扱うときに便利です。

```java
LocalDate today = LocalDate.now();
LocalDate nextYear = today.plus(Period.ofYears(1));
int months = Period.between(today, nextYear).getMonths();
```

## まとめ

実務目線で要点だけ押さえるなら、次の 4 つで十分です。

1. 既存システムでは `Date`、`Calendar`、`SimpleDateFormat` にまだ出会う。
2. 新規実装では `java.time` を優先する。
3. タイムゾーンが絡むなら `Instant` か `ZonedDateTime` を先に検討する。
4. 日付だけでよいなら `LocalDate` が扱いやすい。

Java の日付・時刻 API は、古い設計を少しずつ整理してきた歴史そのものです。この流れを理解しておくと、レガシーコードを読むときも、新しい設計を考えるときも、どの型を選ぶべきか判断しやすくなります。