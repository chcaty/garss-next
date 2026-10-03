# 拾阅 design
## Direction
阅读目录：索引、文章与同步记录共用白色页面、深蓝文字、钴蓝选择标记和细分隔线。阅读与操作优先，文章详情用独立专注视图。方向候选：邮箱工作台、数字报刊、书签书架、播客队列、文献索引、终端监控、阅读目录；采用第七项。
## Reasoning
保留表格和索引的扫描精度、清晰的状态文字与一致导航。光谱轨道、角色商品目录、地铁磁贴、玻璃时刻表、交通图和磁带包装在产品清晰度与用户熟悉度上均弱于阅读目录。分别吸收其状态区分、完整的内容标签、明确的导航入口、数据列对齐、响应式保留上下文、阅读队列连续性纪律，不采用装饰语言。
## Tokens
Paper #f5f7fb; panel #ffffff; ink #17243b; muted #57657a; rule #dbe2ec; accent #2455c6; selected #eaf0ff. Inputs and buttons minimum 44px. Body uses installed CJK sans; article reading uses CJK serif. Page titles are direct functional labels.
## Surfaces
信息流：Read / Operate. 来源筛选、关键词、未读与稍后读进入专注阅读。
订阅源：Operate. 状态筛选、分页、编辑、候选确认和异常归档。
同步记录：Operate. 最近已发布采集、正常异常来源、历史批次、发现状态和 Actions 日志。
## Responsive and states
390px 手机单列，来源横向选择；桌面保留索引栏。加载、数据缺失、采集失败、空筛选与草稿状态使用明确说明。同步历史上限30次，不宣称失败流程已发布。

## Android and identity
Android 使用原生 Material 组件、语义颜色与最小 48dp 触摸区域；宽屏提供导航侧栏。信息流先筛选，稍后读与详情连续专注阅读；四个主入口避免把同步错误混入文章。外观图标在阅读详情中也可访问。品牌为钴蓝书页与浅蓝书签，产品名称拾阅。旧收藏不迁移。

## Reader refinements
分类和北京时间筛选属于阅读任务，与未读、来源和关键词可组合。桌面在列表上方显示筛选；Android 以「分类与时间」打开原生底部面板，避免占满阅读首屏。侧栏显示未读数量，键盘选中行使用现有蓝色选择色。提交来源使用 GitHub 登录确认和 CI 应用，检查窗口不收集凭据；明确区分草稿、已打开确认页与实际发布。
