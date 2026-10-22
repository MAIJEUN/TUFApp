import 'package:flutter/material.dart';

import '../../../app/controllers.dart';
import '../../../app/paged_list.dart';
import '../../../core/l10n.dart';
import '../../../core/tuf_api_client.dart';
import '../../widgets/common.dart';
import '../../widgets/motion.dart';
import '../../widgets/smooth_scroll.dart';
import 'profile_list_view.dart';

/// 플레이어·제작자 페이지의 공통 틀. 레벨 화면과 같은 모양이다:
/// 위 막대, 가운데 정렬된 내용(머리글 카드와 모듈), 맨 아래 긴 목록(기록 · 레벨).
/// 긴 목록은 페이지와 함께 스크롤하고, 끝에 가까워지면 다음 묶음을 불러온다.
class ProfilePageFrame<T> extends StatefulWidget {
  const ProfilePageFrame({
    super.key,
    required this.load,
    required this.titleOf,
    required this.builder,
    this.createList,
    this.listHeader,
    this.itemBuilder,
    this.emptyTitle,
  });

  /// 페이지 내용을 받아 온다.
  final Future<T> Function(BuildContext context) load;
  final String Function(T data) titleOf;

  /// 머리글과 모듈들.
  final List<Widget> Function(BuildContext context, T data) builder;

  /// 맨 아래 긴 목록. 없으면 null.
  final PagedList<Object>? Function(TufApiClient api, T data)? createList;
  final Widget Function(BuildContext context, T data, PagedList<Object> list)? listHeader;
  final Widget Function(BuildContext context, T data, PagedList<Object> list, int index)? itemBuilder;

  /// 목록이 비었을 때의 제목. 없으면 '아무것도 없어요'.
  final String? emptyTitle;

  /// 내용 폭 (모든 화면과 같다).
  static const maxWidth = pageMaxWidth;

  @override
  State<ProfilePageFrame<T>> createState() => _ProfilePageFrameState<T>();
}

class _ProfilePageFrameState<T> extends State<ProfilePageFrame<T>> {
  final _scroll = SmoothScrollController();
  T? _data;
  PagedList<Object>? _list;
  String? _error;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _list?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final data = await widget.load(context);
      if (!mounted) return;
      _list?.dispose();
      final list = widget.createList?.call(AppScope.of(context).api, data);
      list?.addListener(_onListChanged);
      setState(() {
        _data = data;
        _list = list;
      });
      list?.reload();
    } on TufApiException catch (e) {
      if (mounted) setState(() => _error = e.statusCode == 404 ? tr('찾을 수 없어요', 'Not found') : e.message);
    }
  }

  /// 목록이 짧아 화면이 다 차지 않으면 스크롤하지 않아도 이어서 불러온다.
  void _onListChanged() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _maybeLoadMore();
  });

  void _maybeLoadMore() {
    final list = _list;
    if (list == null || !_scroll.hasClients || _scroll.position.extentAfter > 600) return;
    list.loadMore();
  }

  Widget _section(Widget child) => SliverToBoxAdapter(child: _centered(child));

  Widget _centered(Widget child) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: ProfilePageFrame.maxWidth),
      child: SizedBox(
        width: double.infinity,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 24), child: child),
      ),
    ),
  );

  Widget _content(BuildContext context, ScrollBehavior behavior, T data) {
    final list = _list;
    final header = widget.listHeader;
    final item = widget.itemBuilder;
    return CustomScrollView(
      controller: _scroll,
      scrollBehavior: behavior,
      slivers: [
        for (final (index, child) in widget.builder(context, data).indexed)
          _section(index == 0 ? Padding(padding: const EdgeInsets.only(top: 16), child: child) : child),
        if (list != null) ...[
          if (header != null)
            _section(Padding(padding: const EdgeInsets.only(top: 12), child: header(context, data, list))),
          if (item != null)
            SliverList.builder(
              itemCount: list.items.length,
              itemBuilder: (context, index) => _centered(
                Padding(padding: const EdgeInsets.only(bottom: 8), child: item(context, data, list, index)),
              ),
            ),
          _section(ProfileListFooter(list: list, emptyTitle: widget.emptyTitle ?? tr('아무것도 없어요', 'Nothing here'))),
        ],
        const SliverPadding(padding: EdgeInsets.only(bottom: 32)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final error = _error;
    final list = _list;

    final Widget body;
    if (data != null) {
      body = SmoothScrollbar(
        key: const ValueKey('content'),
        controller: _scroll,
        builder: (context, behavior) => list == null
            ? _content(context, behavior, data)
            : ListenableBuilder(listenable: list, builder: (context, _) => _content(context, behavior, data)),
      );
    } else if (error != null) {
      body = Center(
        key: const ValueKey('error'),
        child: EmptyState(
          icon: const Icon(Icons.person_off_outlined),
          title: tr('페이지를 열지 못했어요', "Couldn't open the page"),
          message: error,
          action: FilledButton(onPressed: _load, child: Text(tr('다시 시도', 'Retry'))),
        ),
      );
    } else {
      body = const Center(key: ValueKey('loading'), child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: tr('뒤로', 'Back'),
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(data == null ? '' : widget.titleOf(data)),
      ),
      body: FadeSwitcher(child: body),
    );
  }
}
