---
layout: post
title: "Java インターフェースの進化：default・private メソッドから sealed インターフェースと record まで"
description: "Java 8 から Java 21 までのインターフェースの進化を整理します。default メソッドで公開済み API の後方互換性を保つ仕組み、Java 9 の private メソッドが解決する問題、default メソッドの衝突の解決方法、そして Java 16 の record と Java 17 の sealed インターフェースを Java 21 の switch パターンマッチングと組み合わせる使い方を、Python の dataclass との比較とあわせて紹介します。"
author: Mark_Mew
categories: [Java]
tags: [Java, Interface, Record, Sealed, Pattern Matching, Python]
keywords: [Java インターフェース, Java default メソッド, Java private メソッド, Java 8 default メソッド, Java 9 private メソッド, sealed インターフェース, permits, Java record, レコードパターン, switch パターンマッチング, Java 21, dataclass]
lang: ja
date: 2026-11-24
---

Java 8 以降、インターフェースには抽象メソッドと定数だけでなく、default・static・private メソッドが書けるようになりました。さらに record、sealed インターフェース、パターンマッチングの登場で、インターフェースの使い方も変わってきました。

この記事では、これらの変化をバージョンごとに整理し、各機能が解決する問題を例とあわせて説明します。

## バージョン別の概要

Java 9 以降、インターフェースに書けるメンバーの種類は増えていません。それ以降の変更は、sealed やパターンマッチングのように「インターフェースをどう使えるか」に関するものです。

| バージョン | 追加された内容 | アクセス修飾子 |
| --- | --- | --- |
| Java 7 以前 | 抽象メソッド、定数 | メソッドは `public abstract`、定数は `public static final` |
| Java 8 | `default` メソッド、`static` メソッド | `public` でなければならない |
| Java 9 | `private` メソッド、`private static` メソッド | `private`、かつメソッド本体が必須 |
| Java 16 | record がインターフェースを `implements` できる、ローカルインターフェースの宣言 | — |
| Java 17 | `sealed` インターフェース（`permits`） | — |
| Java 21 | `switch` のパターンマッチング、レコードパターン、sealed と組み合わせた網羅性チェック | — |

> インターフェースでは現在も `protected` メソッドは使えません。
{: .prompt-info}

## Java 8：default メソッド

default メソッドの主な目的は、**公開済みのインターフェースにメソッドを追加しても既存の実装クラスがコンパイルエラーにならず、なおかつ機能を拡張できること**です。JDK 自身もこの仕組みを使って、`Iterable` や `Collection` に `forEach()` や `stream()` を追加しました。

### 例：公開済みのライブラリにメソッドを追加する

v1.0 のライブラリがすでに多くの人に使われていて、`Circle implements Shape` のような実装クラスが書かれているとします。それらのコードは見ることも変更することもできません。

```java
public interface Shape {
    double area();
}
```

**Java 7 の書き方**：抽象メソッドをそのまま追加すると、利用者がアップグレードした時点ですべての実装クラスがコンパイルエラーになります。

```java
public interface Shape {
    double area();
    String describe();   // v2.0 で追加 → 既存の実装がすべて壊れる
}
```

**Java 8 の書き方**：`default` でデフォルト実装を提供すれば、利用者はコードを一切変更する必要がなく、必要ならオーバーライドもできます。

```java
public interface Shape {
    double area();

    default String describe() {
        return "面積：" + area();
    }
}
```

### Java 8 以前の代替手段

default メソッドがなかった頃、JDK は次のような方法で対応していましたが、それぞれ欠点があります。

| 方法 | JDK の例 | 欠点 |
| --- | --- | --- |
| サブインターフェースを新設 | `LayoutManager2 extends LayoutManager` | 利用側のあちこちで `instanceof` の判定が必要になり、API がばらばらになる |
| static ユーティリティクラス | `Collections` | メソッドがインターフェースに属さないため見つけにくく、実装ごとにオーバーライドできない |
| インターフェース + 骨格実装（抽象クラス） | `List` + `AbstractList` | クラスが一つ増え、単一継承の制約を受ける |

### その他のメリット

- 実装クラスごとに同じコードを繰り返す必要がなく、本当に異なる部分だけを実装すればよい。
- 抽象クラスより柔軟：クラスは一つの親クラスしか `extends` できないが、インターフェースは複数 `implements` できる。
- 関数型インターフェースでも、ラムダで実装する抽象メソッド以外に便利なメソッドを提供できる。たとえば `Comparator` の `reversed()` や `thenComparing()`：

```java
Comparator<Person> byAge = (a, b) -> a.age - b.age;
Comparator<Person> c = byAge.reversed().thenComparing(p -> p.name);
```

### 使い分けの原則

実装によって変わる振る舞いは抽象メソッドに任せます。default メソッドは「すべての実装に共通で、インターフェースの他のメソッドを組み合わせて実現できる」機能に向いています。

## Java 9：private メソッド

private メソッドを使うと、複数の default メソッドで内部ロジックを共有しつつ、補助メソッドを公開 API にせずに済みます。

Java 8 より前のインターフェースには実装がまったくなかったため、private は不要でした。default メソッドが登場して、初めて必要になりました。

### Java 8 での問題

```java
public interface Shape {
    double area();

    default String describe() { return "面積：" + fmt(area()); }
    default String toJson()   { return "{\"area\": " + fmt(area()) + "}"; }

    default String fmt(double d) {     // Java 8 では public にしかできない
        return String.format("%.2f", d);
    }
}
```

`fmt` はただの内部用補助メソッドですが、Java 8 では public にするしかなく、次のような問題が起きます。

- 外部から `shape.fmt(...)` を呼び出せるため、使うべき API だと誤解される。
- 実装クラスが誤って `fmt` をオーバーライドすると、`describe()` の出力が変わり、原因を追いにくい。
- 後から `fmt` のシグネチャを変えると、それを呼び出しているコードが壊れる。
- 公開したくなければ、各 default メソッドにロジックをコピーするしかない。

### Java 9 の書き方

```java
    private String fmt(double d) {
        return String.format("%.2f", d);
    }
```

キーワードを一つ変えるだけで、外部からは見えず、実装クラスからはオーバーライドできず、作者はいつでも変更できるようになります。

### ルール

- private メソッドにはメソッド本体が必須で、抽象メソッドにはできない。
- private インスタンスメソッドは、default メソッドか他の private インスタンスメソッドからしか呼び出せない。
- private static メソッドは、static メソッドと非 static メソッドのどちらからでも呼び出せる。

### default と private の役割分担

default メソッドは「利用者に対する」互換性の問題を、private メソッドは「ライブラリ作者にとっての」コード整理の問題を解決します。

どちらの課題も、主にインターフェースがすでに公開され、他の人が実装している場面で表面化します。自分のプロジェクト内だけで使うインターフェースなら、あまり実感しないでしょう。

## default メソッドの衝突

インターフェースが実装を持てるようになったことで、新たな問題が生まれました。あるクラスが二つのインターフェースを実装していて、両方に同じ名前・同じ引数の default メソッドがある場合、どちらが使われるのでしょうか。

Java では、クラス側でオーバーライドすることが求められ、`A.super.method()` でどちらのバージョンを使うか指定できます。

```java
interface A { default String hello() { return "A"; } }
interface B { default String hello() { return "B"; } }

class C implements A, B {
    @Override
    public String hello() {
        return A.super.hello();   // A のバージョンを明示的に使う
    }
}
```

また、インターフェースは `extends` で一つ以上のインターフェースを継承できます。例：`interface C extends A, B {}`。

## Java 16：record

record は「データを保持するだけ」の不変クラスです。一行の宣言で、コンストラクタ、アクセサ、`equals`、`hashCode`、`toString` といったボイラープレートコードを書かずに済みます。

```java
public record Point(int x, int y) {}

Point p = new Point(1, 2);
p.x();                         // 1（getX() ではなく x()）
p.equals(new Point(1, 2));     // true、内容で比較
System.out.println(p);         // Point[x=1, y=2]
```

### 特徴

- フィールドは `private final` で不変、setter はない。
- 暗黙的に `final`：継承できず、他のクラスを `extends` することもできないが、**インターフェースは `implements` できる**。
- 独自のメソッドを追加でき、コンパクトコンストラクタで検証も行える：

```java
public record Point(int x, int y) {
    public Point {                       // 引数リストは不要
        if (x < 0 || y < 0)
            throw new IllegalArgumentException("座標は負にできません");
    }

    public double distanceToOrigin() {
        return Math.sqrt(x * x + y * y);
    }
}
```

record は DTO、メソッドから複数の値を返す場合、Map のキー、設定値などに向いています。可変な状態や複雑な継承が必要な場合は、通常のクラスを使います。

## Java 17：sealed インターフェースと Java 21 のパターンマッチング

sealed インターフェースは、実装できるクラスを制限します。Java 21 の `switch` パターンマッチングと組み合わせると、すべてのケースを処理しているかをコンパイラがチェックしてくれます。

これは default メソッドとは逆の方向性です。

- **default**：他の人に実装してもらい、自分は引き続き機能を拡張できる。
- **sealed**：すべての実装を自分で管理する。

### permits が必要な場合

| 実装クラスの場所 | `permits` |
| --- | --- |
| sealed インターフェースと同じソースファイル | 省略可。コンパイラが自動で推論する |
| 別のファイルに分散 | 必須。かつ同じモジュール（モジュールがない場合は同じパッケージ）にある必要がある |

```java
// 同じファイル：permits を省略
public sealed interface Shape {
    record Circle(double r) implements Shape {}
    record Square(double side) implements Shape {}
}
```

```java
// 別のファイル：permits が必須
public sealed interface Shape permits Circle, Square {}
```

sealed 型を直接実装するクラスには、`final`、`sealed`、`non-sealed` のいずれかを付ける必要があります。record は暗黙的に `final` なので何も付ける必要がなく、**sealed インターフェース + record** が最も簡潔な組み合わせになります。

### Java 21 の switch とレコードパターンとの組み合わせ

```java
double area(Shape s) {
    return switch (s) {
        case Circle c          -> Math.PI * c.r() * c.r();
        case Square(double a)  -> a * a;
        // default は不要。コンパイラはこの二つしかないことを知っている
    };
}
```

後から `permits` に `Triangle` を追加すると、`Triangle` を処理していない `switch` はすべてコンパイルエラーになり、追加し忘れを防げます。

## Python との比較

Java の record に最も近いのは、Python の `@dataclass(frozen=True)` や `typing.NamedTuple` です。

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Point:
    x: int
    y: int
```

| 項目 | Java record | Python dataclass |
| --- | --- | --- |
| 可変性 | 常に不変 | デフォルトは可変、`frozen=True` で不変 |
| 継承 | 継承することも、されることもできない | 自由に継承できる |
| 柔軟性 | フィールドがそのままコンストラクタの引数になり、すべて `equals` の対象 | デフォルト値、`default_factory`、比較対象からのフィールド除外に対応 |
| 自動生成 | コンストラクタ、アクセサ、`equals`、`hashCode`、`toString` | `__init__`、`__repr__`、`__eq__`（frozen の場合は `__hash__` も） |

Java 21 のレコードパターンは、Python 3.10 の `match` に相当します。

```python
match shape:
    case Circle(r=r):
        ...
    case Square(side=a):
        ...
```

## まとめ

- **Java 8 の default メソッド**：公開済みのインターフェースに、既存の実装を壊さずにメソッドを追加できる。
- **Java 9 の private メソッド**：補助メソッドを公開せずに、default メソッド間で内部ロジックを共有できる。
- **Java 16 の record**：不変のデータクラスを一行で宣言でき、インターフェースも実装できる。
- **Java 17 の sealed + Java 21 のパターンマッチング**：実装できる型を限定し、`switch` がすべてのケースを処理しているかをコンパイラにチェックさせられる。

最初の二つは、インターフェースを「他の人が実装できる」形で公開するときの保守性を高めます。残りの二つは、「実装の範囲が決まっている」場面で、インターフェースを型安全なデータモデルとして使えるようにします。
