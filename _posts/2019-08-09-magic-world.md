---
layout: post
title: 避免使用魔術數字
author: Mark_Mew
category: 重構
date: 2019-8-9
---

軟體開發時

有時候在調用函式或方法

會直接給定一個定值

而非宣告變數後，再直接用變數帶入參數中

有時候宣告變數

不僅僅只是為了程式區塊的操作

更多時候是為了增加程式的可讀性

以下方程式為例

```java
// Java code with syntax highlighting
@Controller
@RequestMapping(value = "/api")
public class ApiController {
	@RequestMapping(value = "/{bookId}", method = RequestMethod.GET)
	public @ResponseBody APIResponse findBookInfo(Model model,
	    HttpSession session,
	    @RequestParam(value = "keyword", required = true) String keyword) {
		APIResponse response = new APIResponse();
		Member member = session.getAttribute("Member");
		try {
	    	List result = this.BookService.getBookInfo(member, keyword, 15, 1);
			response.setReturnCode(200);
			response.setData(result);
		} catch(Exception e) {
			response.setReturnCode(500);
			response.setErrMessage(e.getMessage());
		}
		return response;
	}
}
```

調用service

但是卻未宣告變數給值

而是直接給定值

反而會增加日後維護程式碼的成本

需要先判斷或理解一下程式碼的前後有無特殊邏輯的應用

甚至變的不敢任意更動程式碼

若適時的調整內容

```java
// Java code with syntax highlighting
@Controller
@RequestMapping(value = "/api")
public class ApiController {
	@RequestMapping(value = "/{bookId}", method = RequestMethod.GET)
	public @ResponseBody APIResponse findBookInfo(Model model,
	    HttpSession session,
	    @RequestParam(value = "keyword", required = true) String keyword) {
		APIResponse response = new APIResponse();
		Member member = session.getAttribute("Member");
		Integer defaultPageCount = 15;
		Integer defaultPage = 1;
		try {
	    	List result = this.BookService.getBookInfo(member, keyword, defaultPageCount, defaultPage);
			response.setReturnCode(200);
			response.setData(result);
		} catch(Exception e) {
			response.setReturnCode(500);
			response.setErrMessage(e.getMessage());
		}
		return response;
	}
}
```

即使只是簡單的更動

但是能夠很清楚的閱讀

知道這兩個參數的意義是甚麼

因此若有需要帶入參數

此時使用區域變數

可增加一些程式的可讀性

有機會使程式日後可好維護