import 'dart:async';

import 'package:flutter/material.dart';

import '../controller/markdown_stream_controller.dart';
import '../highlight/highlighter.dart';
import '../parser/options.dart';
import '../theme/markdown_theme.dart';
import 'block_view.dart';
import 'render_config.dart';

/// Renders Markdown that is still being streamed in, without jank.
///
/// Three ways to feed it:
///
/// * [StreamingMarkdown.new] renders a [MarkdownStreamController] you drive
///   with `append`/`complete` (the most flexible, and the one to use when the
///   same message is shown in several places).
/// * [StreamingMarkdown.fromStream] subscribes to a `Stream<String>` of
///   tokens and completes when the stream is done.
/// * [StreamingMarkdown.static] renders a finished string.
///
/// Only the block that is currently being written is rebuilt for each new
/// token; finished blocks are skipped by identity.
///
/// The look comes from, in order: the [theme] argument, a [MarkdownTheme]
/// registered in `ThemeData.extensions`, or a theme derived from the ambient
/// `ThemeData`.
///
/// Callbacks and builders are part of the configuration: pass stable function
/// references (not new closures on every build) if you want finished blocks
/// to stay un-rebuilt when the parent widget rebuilds.
class StreamingMarkdown extends StatefulWidget {
  /// Renders the document held by [controller].
  const StreamingMarkdown({
    super.key,
    required MarkdownStreamController this.controller,
    this.theme,
    this.selectable = true,
    this.onTapLink,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.mathBuilder,
    this.thinkingBuilder,
    this.citationBuilder,
    this.onTapCitation,
    this.highlighter = const CodeHighlighter.defaults(),
  }) : stream = null,
       data = null,
       parserOptions = const MarkdownParserOptions(),
       onStreamError = null;

  /// Renders the Markdown arriving on [stream].
  ///
  /// The widget owns the subscription and an internal controller. The
  /// controller is completed when the stream is done (or fails; see
  /// [onStreamError]). Keep the stream instance stable across rebuilds:
  /// passing a different one restarts rendering from scratch.
  const StreamingMarkdown.fromStream({
    super.key,
    required Stream<String> this.stream,
    this.parserOptions = const MarkdownParserOptions(),
    this.onStreamError,
    this.theme,
    this.selectable = true,
    this.onTapLink,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.mathBuilder,
    this.thinkingBuilder,
    this.citationBuilder,
    this.onTapCitation,
    this.highlighter = const CodeHighlighter.defaults(),
  }) : controller = null,
       data = null;

  /// Renders the complete Markdown string [data] (no streaming involved).
  const StreamingMarkdown.static({
    super.key,
    required String this.data,
    this.parserOptions = const MarkdownParserOptions(),
    this.theme,
    this.selectable = true,
    this.onTapLink,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.mathBuilder,
    this.thinkingBuilder,
    this.citationBuilder,
    this.onTapCitation,
    this.highlighter = const CodeHighlighter.defaults(),
  }) : controller = null,
       stream = null,
       onStreamError = null;

  /// The externally owned controller, for the default constructor.
  final MarkdownStreamController? controller;

  /// The token stream, for [StreamingMarkdown.fromStream].
  final Stream<String>? stream;

  /// The finished text, for [StreamingMarkdown.static].
  final String? data;

  /// Parser features, for the stream and static constructors. (With an
  /// external controller, configure the controller instead.)
  final MarkdownParserOptions parserOptions;

  /// Called when [stream] emits an error. If `null` the error is reported
  /// through [FlutterError.reportError]. Either way, rendering is completed.
  final void Function(Object error, StackTrace stackTrace)? onStreamError;

  /// Overrides the theme; `null` uses the ambient [MarkdownTheme].
  final MarkdownTheme? theme;

  /// Whether the text can be selected (wraps the content in a
  /// [SelectionArea]).
  final bool selectable;

  /// Called when a safe link (`http`, `https`, `mailto`, `tel` or relative)
  /// is tapped. Without it links are styled but inert.
  final MarkdownLinkCallback? onTapLink;

  /// Builds image widgets; by default an alt-text placeholder is shown and
  /// nothing is fetched from the network.
  final MarkdownImageBuilder? imageBuilder;

  /// Replaces the default code block widget.
  final MarkdownCodeBlockBuilder? codeBlockBuilder;

  /// Typesets LaTeX math. Without it the TeX source is shown in the code
  /// style. See [MarkdownMathBuilder].
  final MarkdownMathBuilder? mathBuilder;

  /// Renders `<think>…</think>` sections. Without it, a collapsible section
  /// is shown. See [MarkdownThinkingBuilder].
  final MarkdownThinkingBuilder? thinkingBuilder;

  /// Renders citation markers such as `[1]`. Takes precedence over
  /// [onTapCitation]. See [MarkdownCitationBuilder].
  final MarkdownCitationBuilder? citationBuilder;

  /// Called when a citation label is tapped; makes the labels look like
  /// links. Without it (and without [citationBuilder]) citations look like
  /// the original text.
  final MarkdownCitationCallback? onTapCitation;

  /// Tokenizes code for syntax highlighting.
  final CodeHighlighter highlighter;

  @override
  State<StreamingMarkdown> createState() => _StreamingMarkdownState();
}

class _StreamingMarkdownState extends State<StreamingMarkdown> {
  late MarkdownStreamController _controller;
  bool _owned = false;
  StreamSubscription<String>? _subscription;
  MarkdownRenderConfig? _config;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final external = widget.controller;
    if (external != null) {
      _controller = external;
      _owned = false;
    } else {
      _owned = true;
      final stream = widget.stream;
      _controller = MarkdownStreamController(
        options: widget.parserOptions,
        coalesceNotifications: stream != null,
      );
      if (stream != null) {
        _subscription = stream.listen(
          _controller.append,
          onError: _onStreamError,
          onDone: _controller.complete,
        );
      } else {
        _controller
          ..append(widget.data ?? '')
          ..complete();
      }
    }
    _controller.addListener(_onChanged);
  }

  void _detach() {
    _controller.removeListener(_onChanged);
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (_owned) _controller.dispose();
  }

  void _onStreamError(Object error, StackTrace stackTrace) {
    _controller.complete();
    final handler = widget.onStreamError;
    if (handler != null) {
      handler(error, stackTrace);
    } else {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'llm_markdown_renderer',
          context: ErrorDescription('while reading the Markdown stream'),
        ),
      );
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(StreamingMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.stream != widget.stream ||
        oldWidget.data != widget.data) {
      _detach();
      _attach();
    }
    _config = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _config = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  MarkdownRenderConfig _resolveConfig(BuildContext context) {
    final next = MarkdownRenderConfig(
      theme: widget.theme ?? MarkdownTheme.of(context),
      highlighter: widget.highlighter,
      onTapLink: widget.onTapLink,
      imageBuilder: widget.imageBuilder,
      codeBlockBuilder: widget.codeBlockBuilder,
      mathBuilder: widget.mathBuilder,
      thinkingBuilder: widget.thinkingBuilder,
      citationBuilder: widget.citationBuilder,
      onTapCitation: widget.onTapCitation,
    );
    final old = _config;
    // Keep the previous object when nothing changed so finished blocks stay
    // equal (and are therefore not rebuilt).
    if (old != null &&
        old.theme == next.theme &&
        old.highlighter == next.highlighter &&
        old.onTapLink == next.onTapLink &&
        old.imageBuilder == next.imageBuilder &&
        old.codeBlockBuilder == next.codeBlockBuilder &&
        old.mathBuilder == next.mathBuilder &&
        old.thinkingBuilder == next.thinkingBuilder &&
        old.citationBuilder == next.citationBuilder &&
        old.onTapCitation == next.onTapCitation) {
      return old;
    }
    return _config = next;
  }

  @override
  Widget build(BuildContext context) {
    final config = _resolveConfig(context);
    final blocks = _controller.document.blocks;
    final Widget content = BlockColumn(
      blocks: blocks,
      config: config,
      textStyle: config.theme.bodyStyle,
      gap: config.theme.blockSpacing,
    );
    return widget.selectable ? SelectionArea(child: content) : content;
  }
}
