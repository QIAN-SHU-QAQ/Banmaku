import 'dart:async';
import 'dart:ui' show PointerDeviceKind;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../shared/widgets/desktop_page_header.dart';
import 'airing_schedule.dart';

const _daysPerPage = 7;
const _weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

DateTime _addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

String _dateLabel(DateTime date) => '${date.month}月${date.day}日';

String _timeLabel(DateTime time) =>
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key, this.load, this.now = DateTime.now});

  final AiringScheduleLoader? load;
  final DateTime Function() now;

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  late final AiringScheduleLoader _load =
      widget.load ?? AiringScheduleRepository().load;
  late DateTime _start = _addDays(widget.now(), 0);
  late Future<List<AiringEpisode>> _schedule;
  CancelToken? _cancelToken;
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _request();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    _cancelToken?.cancel();
    super.dispose();
  }

  void _request() {
    _cancelToken?.cancel();
    final cancelToken = _cancelToken = CancelToken();
    _schedule = _load(
      _start,
      _addDays(_start, _daysPerPage),
      cancelToken: cancelToken,
    );
  }

  void _show(DateTime start) {
    setState(() {
      _start = start;
      _request();
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = widget.now();
    final today = _addDays(now, 0);
    final lastDay = _addDays(_start, _daysPerPage - 1);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DesktopPageHeader(
              title: '新番时间表',
              leading: const BackButton(),
              actions: [
                TextButton(
                  onPressed: _start == today ? null : () => _show(today),
                  child: const Text('回到今天'),
                ),
                IconButton(
                  tooltip: '前 7 天',
                  onPressed: () => _show(_addDays(_start, -_daysPerPage)),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                IconButton(
                  tooltip: '后 7 天',
                  onPressed: () => _show(_addDays(_start, _daysPerPage)),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text(
                    '${_start.year}年${_dateLabel(_start)} – '
                    '${_start.year == lastDay.year ? '' : '${lastDay.year}年'}'
                    '${_dateLabel(lastDay)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'AniList · 本机时间',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: FutureBuilder(
                future: _schedule,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        semanticsLabel: '正在加载放送安排',
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _ScheduleMessage(
                      icon: Icons.cloud_off_rounded,
                      title: '无法加载放送时间表',
                      action: FilledButton.tonal(
                        onPressed: () => setState(_request),
                        child: const Text('重试'),
                      ),
                    );
                  }
                  final episodes = snapshot.requireData;
                  if (episodes.isEmpty) {
                    return const _ScheduleMessage(
                      icon: Icons.event_busy_rounded,
                      title: '这 7 天暂无放送安排',
                    );
                  }
                  return _ScheduleBoard(
                    key: ValueKey(_start),
                    start: _start,
                    now: now,
                    episodes: episodes,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScheduleMessage extends StatelessWidget {
  const _ScheduleMessage({
    required this.icon,
    required this.title,
    this.action,
  });

  final IconData icon;
  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: theme.textTheme.titleMedium),
            if (action != null) ...[const SizedBox(height: 16), action!],
          ],
        ),
      ),
    );
  }
}

class _ScheduleBoard extends StatefulWidget {
  const _ScheduleBoard({
    super.key,
    required this.start,
    required this.now,
    required this.episodes,
  });

  final DateTime start;
  final DateTime now;
  final List<AiringEpisode> episodes;

  @override
  State<_ScheduleBoard> createState() => _ScheduleBoardState();
}

class _ScheduleBoardState extends State<_ScheduleBoard> {
  final _horizontal = ScrollController();
  final _vertical = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const inset = 24.0;
    const gap = 10.0;
    final today = _addDays(widget.now, 0);
    final dates = List.generate(_daysPerPage, (i) => _addDays(widget.start, i));
    final byDate = <DateTime, List<AiringEpisode>>{
      for (final date in dates) date: [],
    };
    for (final episode in widget.episodes) {
      byDate[_addDays(episode.airingAt.toLocal(), 0)]?.add(episode);
    }
    for (final episodes in byDate.values) {
      episodes.sort((a, b) => a.airingAt.compareTo(b.airingAt));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final minWidths = [
          for (final date in dates) date == today ? 274.0 : 248.0,
        ];
        final minWidth =
            inset * 2 +
            gap * (_daysPerPage - 1) +
            minWidths.reduce((a, b) => a + b);
        final needsHorizontalScroll = constraints.maxWidth < minWidth;
        final addedWidth =
            needsHorizontalScroll
                ? 0.0
                : (constraints.maxWidth - minWidth) / _daysPerPage;
        final scrollBehavior = ScrollConfiguration.of(context);
        return ScrollConfiguration(
          behavior: scrollBehavior.copyWith(
            scrollbars: false,
            dragDevices: {
              ...scrollBehavior.dragDevices,
              PointerDeviceKind.mouse,
            },
          ),
          child: Scrollbar(
            controller: _horizontal,
            thumbVisibility: needsHorizontalScroll,
            scrollbarOrientation: ScrollbarOrientation.bottom,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: inset),
              child: SizedBox(
                height: constraints.maxHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      spacing: gap,
                      children: [
                        for (var i = 0; i < dates.length; i++)
                          SizedBox(
                            width: minWidths[i] + addedWidth,
                            child: _DateHeader(
                              date: dates[i],
                              isToday: dates[i] == today,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: Scrollbar(
                        controller: _vertical,
                        child: SingleChildScrollView(
                          controller: _vertical,
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Row(
                            spacing: gap,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              for (var i = 0; i < dates.length; i++)
                                SizedBox(
                                  width: minWidths[i] + addedWidth,
                                  child: _DayEpisodes(
                                    episodes: byDate[dates[i]]!,
                                    now: dates[i] == today ? widget.now : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.date, required this.isToday});

  final DateTime date;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Semantics(
      header: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: isToday ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isToday
                    ? '${_weekdays[date.weekday - 1]} · 今天'
                    : _weekdays[date.weekday - 1],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelLarge?.copyWith(
                  color:
                      isToday
                          ? colors.onPrimaryContainer
                          : colors.onSurfaceVariant,
                ),
              ),
              Text(
                _dateLabel(date),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: isToday ? colors.onPrimaryContainer : colors.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DayEpisodes extends StatelessWidget {
  const _DayEpisodes({required this.episodes, required this.now});

  final List<AiringEpisode> episodes;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final currentTime = now;
    var markerIndex = episodes.length;
    if (currentTime != null) {
      final next = episodes.indexWhere(
        (episode) => episode.airingAt.isAfter(currentTime),
      );
      if (next != -1) markerIndex = next;
    }
    final rows = episodes.map<Widget>(_EpisodeTile.new).toList();
    if (currentTime != null) {
      rows.insert(
        markerIndex,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            spacing: 8,
            children: [
              Icon(Icons.schedule_rounded, size: 16, color: colors.primary),
              Text(
                _timeLabel(currentTime),
                semanticsLabel: '当前时间 ${_timeLabel(currentTime)}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.primary,
                ),
              ),
              Expanded(child: Divider(color: colors.outlineVariant)),
            ],
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color:
            currentTime != null
                ? Color.alphaBlend(
                  colors.primary.withValues(alpha: 0.06),
                  colors.surface,
                )
                : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child:
            rows.isEmpty
                ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  child: Text(
                    '暂无安排',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                )
                : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 6,
                  children: rows,
                ),
      ),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile(this.episode);

  final AiringEpisode episode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = _timeLabel(episode.airingAt.toLocal());
    const radius = BorderRadius.all(Radius.circular(8));
    return Material(
      color: colors.surfaceContainerLowest,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: colors.outlineVariant),
        borderRadius: radius,
      ),
      child: Tooltip(
        message: '搜索 ${episode.title}',
        child: InkWell(
          borderRadius: radius,
          onTap:
              () => context.push(
                Uri(
                  path: '/search',
                  queryParameters: {'q': episode.title, 'from': 'schedule'},
                ).toString(),
              ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: colors.primary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Cover(url: episode.coverUrl),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            episode.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '第 ${episode.episode} 集',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: colors.surfaceContainer,
      child: Icon(
        Icons.image_outlined,
        color: colors.onSurfaceVariant,
        size: 17,
      ),
    );
    return ExcludeSemantics(
      child: SizedBox(
        width: 36,
        height: 52,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child:
              url == null
                  ? fallback
                  : CachedNetworkImage(
                    imageUrl: url!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => fallback,
                    errorWidget: (_, _, _) => fallback,
                  ),
        ),
      ),
    );
  }
}
