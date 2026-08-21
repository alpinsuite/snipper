import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../model/annotation.dart';
import '../model/snip.dart';

/// One undoable state of the document.
///
/// A snapshot rather than a diff, and it costs almost nothing: annotations are
/// immutable, so a step is a list of pointers to objects that already exist.
/// That is the payoff for marks being objects instead of pixels — `paint` has
/// to keep bitmaps around for the same feature.
@immutable
class _Step {
  const _Step({required this.annotations, required this.selectedId});

  final List<Annotation> annotations;
  final int? selectedId;
}

/// The snip currently open, the marks on it, and how to take them back.
///
/// Separate from `CaptureController` on purpose: taking a picture and working
/// on one are different jobs with different lifetimes, and a snip outlives the
/// capture that produced it.
class ShotController extends ChangeNotifier {
  Snip? _snip;
  Snip? get snip => _snip;

  bool get hasSnip => _snip != null;

  List<Annotation> _annotations = const <Annotation>[];
  List<Annotation> get annotations => _annotations;

  int? _selectedId;
  int? get selectedId => _selectedId;

  Annotation? get selected {
    final id = _selectedId;
    if (id == null) return null;
    for (final annotation in _annotations) {
      if (annotation.id == id) return annotation;
    }
    return null;
  }

  /// The mark being drawn right now, if any.
  ///
  /// Held apart from [annotations] so a drag in progress is not something undo
  /// can land in the middle of.
  Annotation? _draft;
  Annotation? get draft => _draft;

  final List<_Step> _past = <_Step>[];
  final List<_Step> _future = <_Step>[];

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  int _nextId = 1;

  /// What the next numbered badge will say.
  ///
  /// Counted from the badges that are actually there rather than kept as a
  /// running total, so deleting step 2 and drawing another one gives 2 again
  /// instead of 4.
  int get nextStepNumber {
    var highest = 0;
    for (final annotation in _annotations) {
      if (annotation is StepBadge && annotation.number > highest) {
        highest = annotation.number;
      }
    }
    return highest + 1;
  }

  int takeId() => _nextId++;

  /// Replaces what is open, discarding the marks and the history with it.
  ///
  /// The previous image is disposed here, which makes this the only place a
  /// snip's lifetime ends and keeps the several megabytes a screenshot costs
  /// from accumulating one capture at a time.
  void open(Snip snip) {
    if (identical(_snip, snip)) return;
    _snip?.dispose();
    _snip = snip;
    _annotations = const <Annotation>[];
    _selectedId = null;
    _draft = null;
    _past.clear();
    _future.clear();
    _nextId = 1;
    notifyListeners();
  }

  void close() {
    if (_snip == null) return;
    _snip?.dispose();
    _snip = null;
    _annotations = const <Annotation>[];
    _selectedId = null;
    _draft = null;
    _past.clear();
    _future.clear();
    notifyListeners();
  }

  // -- drawing --------------------------------------------------------------

  /// Shows a mark being drawn. Not undoable, and not part of the document
  /// until [commitDraft].
  void showDraft(Annotation? annotation) {
    if (identical(_draft, annotation)) return;
    _draft = annotation;
    notifyListeners();
  }

  void commitDraft(Annotation annotation) {
    _push();
    _annotations = <Annotation>[..._annotations, annotation];
    _draft = null;
    _selectedId = annotation.id;
    notifyListeners();
  }

  void discardDraft() {
    if (_draft == null) return;
    _draft = null;
    notifyListeners();
  }

  // -- editing --------------------------------------------------------------

  void select(int? id) {
    if (_selectedId == id) return;
    _selectedId = id;
    notifyListeners();
  }

  /// The topmost mark under [point], or null.
  ///
  /// Topmost, because that is the one being looked at: marks are drawn in the
  /// order they were made, so the last one wins the click.
  Annotation? hitTest(ui.Offset point, {double tolerance = 0}) {
    for (var i = _annotations.length - 1; i >= 0; i--) {
      if (_annotations[i].hitTest(point, tolerance: tolerance)) {
        return _annotations[i];
      }
    }
    return null;
  }

  /// Moves a mark. [record] is false for the intermediate frames of a drag, so
  /// one drag is one undo step rather than one per pointer event.
  void move(int id, ui.Offset delta, {bool record = false}) {
    if (delta == ui.Offset.zero) return;
    if (record) _push();
    _annotations = <Annotation>[
      for (final annotation in _annotations)
        if (annotation.id == id) annotation.translated(delta) else annotation,
    ];
    notifyListeners();
  }

  void restyle(int id, AnnotationStyle style) {
    _push();
    _annotations = <Annotation>[
      for (final annotation in _annotations)
        if (annotation.id == id) annotation.restyled(style) else annotation,
    ];
    notifyListeners();
  }

  void replace(Annotation annotation) {
    _push();
    _annotations = <Annotation>[
      for (final existing in _annotations)
        if (existing.id == annotation.id) annotation else existing,
    ];
    notifyListeners();
  }

  void deleteSelected() {
    final id = _selectedId;
    if (id == null) return;
    _push();
    _annotations = <Annotation>[
      for (final annotation in _annotations)
        if (annotation.id != id) annotation,
    ];
    _selectedId = null;
    notifyListeners();
  }

  void clearAnnotations() {
    if (_annotations.isEmpty) return;
    _push();
    _annotations = const <Annotation>[];
    _selectedId = null;
    notifyListeners();
  }

  // -- history --------------------------------------------------------------

  void undo() {
    if (_past.isEmpty) return;
    _future.add(_snapshot());
    final step = _past.removeLast();
    _annotations = step.annotations;
    _selectedId = step.selectedId;
    _draft = null;
    notifyListeners();
  }

  void redo() {
    if (_future.isEmpty) return;
    _past.add(_snapshot());
    final step = _future.removeLast();
    _annotations = step.annotations;
    _selectedId = step.selectedId;
    _draft = null;
    notifyListeners();
  }

  /// How far back it is possible to go.
  ///
  /// Generous, because a step is a handful of pointers. Bounded anyway: an
  /// unbounded stack is a leak that only shows up in a long session.
  static const int historyDepth = 200;

  void _push() {
    _past.add(_snapshot());
    if (_past.length > historyDepth) _past.removeAt(0);
    _future.clear();
  }

  _Step _snapshot() =>
      _Step(annotations: _annotations, selectedId: _selectedId);

  @override
  void dispose() {
    _snip?.dispose();
    _snip = null;
    super.dispose();
  }
}
