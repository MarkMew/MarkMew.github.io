---
layout: post
title: "Java Interface 的演變：從 default、private 方法到 sealed interface 與 record"
description: "整理 Java 8 到 Java 21 之間 interface 的演變：default 方法如何讓已發布的 API 向下相容、Java 9 private 方法解決的問題、多重 default 衝突的處理，以及 Java 16 record、Java 17 sealed interface 搭配 Java 21 switch 模式比對的用法，並與 Python dataclass 對照。"
author: Mark_Mew
categories: [Java]
tags: [Java, Interface, Record, Sealed, Pattern Matching, Python]
keywords: [Java interface, Java default method, Java private interface method, Java 8 default 方法, Java 9 private 方法, sealed interface, permits, Java record, record pattern, switch 模式比對, Java 21, dataclass]
lang: zh-TW
date: 2026-11-24
---

從 Java 8 開始，interface 不再只能宣告 abstract 方法與常數，陸續加入了 default、static、private 方法；之後又有 record、sealed interface 與模式比對，改變了 interface 的使用方式。

本文依版本整理這些變化，說明每個功能要解決的問題，並附上範例。

## 版本總覽

Java 9 之後，interface 能寫的成員種類就沒有再增加了。之後的改動都在「interface 能怎麼被使用」，例如 sealed 與模式比對。

| 版本 | 新增內容 | 存取修飾 |
| --- | --- | --- |
| Java 7 以前 | abstract 方法、常數 | 方法為 `public abstract`；常數為 `public static final` |
| Java 8 | `default` 方法、`static` 方法 | 必須是 `public` |
| Java 9 | `private` 方法、`private static` 方法 | `private`，且必須有方法體 |
| Java 16 | record 可 `implements` interface；可宣告區域 interface | — |
| Java 17 | `sealed` interface（`permits`） | — |
| Java 21 | `switch` 模式比對、record pattern，搭配 sealed 做完整性檢查 | — |

> interface 至今仍不允許 `protected` 方法。
{: .prompt-info}

## Java 8：default 方法

default 方法的核心目的是：**已發布的 interface 要新增方法時，既有的實作類別不會編譯失敗，同時又能升級功能。**JDK 本身就是靠它替 `Iterable`、`Collection` 加上 `forEach()`、`stream()`。

### 情境：替已發布的函式庫加方法

假設 v1.0 的函式庫已經有很多人在用，他們寫了 `Circle implements Shape` 之類的實作，你看不到也改不了：

```java
public interface Shape {
    double area();
}
```

**Java 7 的寫法**：直接加 abstract 方法，使用者一升級，所有實作類別都會編譯失敗。

```java
public interface Shape {
    double area();
    String describe();   // v2.0 新增 → 既有實作全部壞掉
}
```

**Java 8 的寫法**：用 `default` 提供預設實作，使用者不用改任何程式碼，想自訂也可以覆寫。

```java
public interface Shape {
    double area();

    default String describe() {
        return "面積為 " + area();
    }
}
```

### Java 8 以前的替代做法

沒有 default 方法時，JDK 只能用以下幾種方式處理，各有缺點：

| 做法 | JDK 實例 | 缺點 |
| --- | --- | --- |
| 另開子介面 | `LayoutManager2 extends LayoutManager` | 使用端到處寫 `instanceof` 判斷，API 零散 |
| 靜態工具類別 | `Collections` | 方法不屬於 interface，不好找，也無法依實作覆寫 |
| interface + 骨架抽象類別 | `List` + `AbstractList` | 多一個類別，且受限於單一繼承 |

### 其他好處

- 每個實作類別不用重複一樣的程式碼，只需實作真正不同的部分。
- 比 abstract class 有彈性：類別只能 `extends` 一個父類別，卻能 `implements` 多個 interface。
- functional interface 除了用 lambda 實作，還能提供額外功能，例如 `Comparator` 的 `reversed()`、`thenComparing()`：

```java
Comparator<Person> byAge = (a, b) -> a.age - b.age;
Comparator<Person> c = byAge.reversed().thenComparing(p -> p.name);
```

### 使用原則

會因實作而不同的行為，留給 abstract 方法；default 適合「所有實作通用、能靠其他 interface 方法組合出來」的功能。

## Java 9：private 方法

private 方法讓多個 default 方法共用內部邏輯，又不會把輔助方法變成公開 API。

Java 8 以前 interface 沒有任何實作，所以不需要 private。default 方法出現之後，才有了這個需求。

### Java 8 的困境

```java
public interface Shape {
    double area();

    default String describe() { return "面積為 " + fmt(area()); }
    default String toJson()   { return "{\"area\": " + fmt(area()) + "}"; }

    default String fmt(double d) {     // Java 8 只能是 public
        return String.format("%.2f", d);
    }
}
```

`fmt` 只是內部的輔助方法，但在 Java 8 只能是 public，會造成這些問題：

- 外部可以呼叫 `shape.fmt(...)`，會以為這是該用的 API。
- 實作類別可能意外覆寫 `fmt`，導致 `describe()` 的輸出改變，而且難以追查。
- 之後想改 `fmt` 的簽名，會影響有在呼叫它的人。
- 不想公開，就只能把邏輯複製到每個 default 方法裡。

### Java 9 的寫法

```java
    private String fmt(double d) {
        return String.format("%.2f", d);
    }
```

只改一個關鍵字：外部看不到、實作類別覆寫不了，作者也可以隨時修改。

### 規則

- private 方法必須有方法體，不能是 abstract。
- private 實例方法只能被 default 方法或其他 private 實例方法呼叫。
- private static 方法可以被 static 和非 static 方法呼叫。

### default 與 private 的分工

default 方法解決的是「對使用者」的相容性問題；private 方法解決的是「對函式庫作者」的程式碼整理問題。

這兩個痛點主要出現在 interface 已經發布、且有其他人實作的情境。如果 interface 只在自己的專案內部使用，感受就不明顯。

## 多重 default 方法衝突

interface 有了實作之後，就多了一個要處理的問題：類別同時實作兩個 interface，而它們有同名、同參數的 default 方法時，該用哪一個？

Java 的做法是要求類別自行覆寫，並可用 `A.super.method()` 指定要用哪一個版本：

```java
interface A { default String hello() { return "A"; } }
interface B { default String hello() { return "B"; } }

class C implements A, B {
    @Override
    public String hello() {
        return A.super.hello();   // 明確選用 A 的版本
    }
}
```

另外，interface 也可以用 `extends` 繼承一個或多個 interface，例如 `interface C extends A, B {}`。

## Java 16：record

record 是專門用來「單純裝資料」的不可變類別。一行宣告就能取代建構子、存取方法、`equals`、`hashCode`、`toString` 等樣板程式碼：

```java
public record Point(int x, int y) {}

Point p = new Point(1, 2);
p.x();                         // 1（是 x() 不是 getX()）
p.equals(new Point(1, 2));     // true，依內容比較
System.out.println(p);         // Point[x=1, y=2]
```

### 特性

- 欄位為 `private final`，不可變，沒有 setter。
- 隱含 `final`：不能被繼承，也不能 `extends` 其他類別，但**可以 `implements` interface**。
- 可以加自訂方法，也可以用精簡建構子（compact constructor）做驗證：

```java
public record Point(int x, int y) {
    public Point {                       // 不用寫參數列
        if (x < 0 || y < 0)
            throw new IllegalArgumentException("座標不能為負");
    }

    public double distanceToOrigin() {
        return Math.sqrt(x * x + y * y);
    }
}
```

record 適合用在 DTO、方法回傳多個值、Map 的 key、設定值等情境；需要可變狀態或複雜繼承時，仍然使用一般 class。

## Java 17：sealed interface 與 Java 21 模式比對

sealed interface 限制哪些類別能實作它，搭配 Java 21 的 `switch` 模式比對，編譯器就能檢查是否處理了所有情況。

它和 default 方法的方向正好相反：

- **default**：讓別人實作，你還能繼續升級。
- **sealed**：所有實作都由你掌握。

### 何時要寫 permits

| 實作的位置 | `permits` |
| --- | --- |
| 與 sealed interface 在同一個原始檔 | 可省略，編譯器自動推斷 |
| 分散在不同檔案 | 必須寫；且需在同一個 module（沒有 module 時為同一個 package） |

```java
// 同一檔案：省略 permits
public sealed interface Shape {
    record Circle(double r) implements Shape {}
    record Square(double side) implements Shape {}
}
```

```java
// 不同檔案：必須寫 permits
public sealed interface Shape permits Circle, Square {}
```

sealed 型別的直接實作，必須標示 `final`、`sealed` 或 `non-sealed` 三者之一。record 隱含 `final`，什麼都不用加，所以 **sealed interface + record** 是最精簡的組合。

### 搭配 Java 21 switch 與 record pattern

```java
double area(Shape s) {
    return switch (s) {
        case Circle c          -> Math.PI * c.r() * c.r();
        case Square(double a)  -> a * a;
        // 不用寫 default，編譯器知道只有這兩種
    };
}
```

日後在 `permits` 加入 `Triangle`，所有沒有處理 `Triangle` 的 `switch` 都會編譯失敗，提醒你去補上。

## 與 Python 對照

Java record 最接近 Python 的 `@dataclass(frozen=True)` 或 `typing.NamedTuple`：

```python
from dataclasses import dataclass

@dataclass(frozen=True)
class Point:
    x: int
    y: int
```

| 項目 | Java record | Python dataclass |
| --- | --- | --- |
| 可變性 | 一定不可變 | 預設可變，`frozen=True` 才不可變 |
| 繼承 | 不能繼承，也不能被繼承 | 可自由繼承 |
| 彈性 | 欄位即建構子參數，全部參與 `equals` | 支援預設值、`default_factory`，可排除欄位不參與比較 |
| 自動產生 | 建構子、存取方法、`equals`、`hashCode`、`toString` | `__init__`、`__repr__`、`__eq__`（frozen 時含 `__hash__`） |

Java 21 的 record pattern，則對應 Python 3.10 的 `match`：

```python
match shape:
    case Circle(r=r):
        ...
    case Square(side=a):
        ...
```

## 總結

- **Java 8 default 方法**：讓已發布的 interface 能新增方法，而不破壞既有實作。
- **Java 9 private 方法**：讓 default 方法共用內部邏輯，不必公開輔助方法。
- **Java 16 record**：用一行宣告不可變的資料類別，且可以實作 interface。
- **Java 17 sealed + Java 21 模式比對**：限定實作的範圍，讓編譯器檢查 `switch` 是否處理了所有情況。

前兩者讓 interface「開放給別人實作」時更好維護；後兩者則讓 interface 在「實作範圍固定」時，能當成型別安全的資料模型來使用。
