/// Plain row types. Hand-written rather than generated: the native send engine reads
/// and writes the same tables, so the schema is a shared contract that must stay
/// legible on both sides.
library;

import 'dart:convert';

class ContactStatus {
  static const notSent = 'not_sent';
  static const queued = 'queued';
  static const sent = 'sent';
  static const delivered = 'delivered';
  static const failed = 'failed';
  static const replied = 'replied';
  static const doNotContact = 'do_not_contact';

  /// Order used by the Contacts filter chips.
  static const all = [
    notSent,
    queued,
    sent,
    delivered,
    replied,
    failed,
    doNotContact,
  ];

  static String label(String status) => switch (status) {
    notSent => 'Not sent',
    queued => 'Queued',
    sent => 'Sent',
    delivered => 'Delivered',
    failed => 'Failed',
    replied => 'Replied',
    doNotContact => 'Do not contact',
    _ => status,
  };
}

class BatchStatus {
  static const pending = 'pending';
  static const inProgress = 'in_progress';
  static const completed = 'completed';
  static const partial = 'partial';
}

class Contact {
  const Contact({
    required this.id,
    required this.phoneE164,
    required this.phoneLocal,
    required this.name,
    required this.source,
    required this.status,
    required this.batchId,
    required this.lastSentAt,
    required this.lastError,
    required this.attempts,
    required this.isCampaign,
    this.muted = false,
  });

  final int id;
  final String phoneE164;
  final String phoneLocal;
  final String? name;
  final String? source;
  final String status;
  final int? batchId;
  final int? lastSentAt;
  final String? lastError;
  final int attempts;
  final bool isCampaign;

  /// Their messages still arrive and are stored, but silently: no
  /// notification, no unread badge.
  final bool muted;

  String get display =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : phoneLocal;

  factory Contact.fromRow(Map<String, Object?> r) => Contact(
    id: r['id'] as int,
    phoneE164: r['phone_e164'] as String,
    phoneLocal: (r['phone_local'] as String?) ?? (r['phone_e164'] as String),
    name: r['name'] as String?,
    source: r['source'] as String?,
    status: r['status'] as String,
    batchId: r['batch_id'] as int?,
    lastSentAt: r['last_sent_at'] as int?,
    lastError: r['last_error'] as String?,
    attempts: (r['attempts'] as int?) ?? 0,
    isCampaign: ((r['is_campaign'] as int?) ?? 1) == 1,
    muted: ((r['muted'] as int?) ?? 0) == 1,
  );
}

/// What happened when somebody typed a number in by hand.
///
/// Three outcomes, and the UI says something different for each: the number was
/// added to a batch, it was already on the list, or it is not a number this app
/// can send to. Returning them as one value keeps the decision in the
/// repository, where the normalizer already lives.
class ManualAdd {
  const ManualAdd._({
    required this.outcome,
    this.contactId,
    this.batchId,
    this.batchName,
    this.existing,
    this.reason,
  });

  factory ManualAdd.added({
    required int contactId,
    required int batchId,
    required String batchName,
  }) => ManualAdd._(
    outcome: ManualAddOutcome.added,
    contactId: contactId,
    batchId: batchId,
    batchName: batchName,
  );

  factory ManualAdd.duplicate(Contact existing) =>
      ManualAdd._(outcome: ManualAddOutcome.duplicate, existing: existing);

  factory ManualAdd.rejected(String reason) =>
      ManualAdd._(outcome: ManualAddOutcome.rejected, reason: reason);

  final ManualAddOutcome outcome;
  final int? contactId;
  final int? batchId;
  final String? batchName;
  final Contact? existing;
  final String? reason;

  bool get ok => outcome == ManualAddOutcome.added;

  String get message => switch (outcome) {
    ManualAddOutcome.added => 'Added to $batchName.',
    ManualAddOutcome.duplicate =>
      '${existing!.phoneLocal} is already on your list.',
    ManualAddOutcome.rejected =>
      reason ?? 'That is not a number this app can send to.',
  };
}

enum ManualAddOutcome { added, duplicate, rejected }

/// A campaign that exists but has not started: the batch, the words, and when.
class ScheduledCampaign {
  const ScheduledCampaign({
    required this.campaignId,
    required this.batchId,
    required this.batchName,
    required this.template,
    required this.at,
  });

  final int campaignId;
  final int batchId;
  final String batchName;
  final String template;
  final int at;
}

class Batch {
  const Batch({
    required this.id,
    required this.name,
    required this.size,
    required this.status,
    required this.position,
    required this.createdAt,
    required this.completedAt,
    required this.total,
    required this.remaining,
    required this.sent,
    required this.replied,
    required this.failed,
  });

  final int id;
  final String name;
  final int size;
  final String status;

  /// Where the user has put this batch in the sending order.
  final int position;
  final int createdAt;
  final int? completedAt;

  // Live counts joined in by the repository, so the list needs one query not N.
  final int total;
  final int remaining;
  final int sent;
  final int replied;
  final int failed;

  bool get isDone => status == BatchStatus.completed;

  factory Batch.fromRow(Map<String, Object?> r) => Batch(
    id: r['id'] as int,
    name: r['name'] as String,
    size: (r['size'] as int?) ?? 0,
    status: r['status'] as String,
    position: (r['position'] as int?) ?? 0,
    createdAt: (r['created_at'] as int?) ?? 0,
    completedAt: r['completed_at'] as int?,
    total: (r['total'] as int?) ?? 0,
    remaining: (r['remaining'] as int?) ?? 0,
    sent: (r['sent'] as int?) ?? 0,
    replied: (r['replied'] as int?) ?? 0,
    failed: (r['failed'] as int?) ?? 0,
  );
}

class Message {
  const Message({
    required this.id,
    required this.contactId,
    required this.campaignId,
    required this.direction,
    required this.body,
    required this.segments,
    required this.status,
    required this.error,
    required this.createdAt,
    required this.sentAt,
    required this.deliveredAt,
  });

  final int id;
  final int contactId;
  final int? campaignId;
  final String direction;
  final String body;
  final int segments;
  final String status;
  final String? error;
  final int createdAt;
  final int? sentAt;
  final int? deliveredAt;

  bool get isInbound => direction == 'inbound';

  factory Message.fromRow(Map<String, Object?> r) => Message(
    id: r['id'] as int,
    contactId: r['contact_id'] as int,
    campaignId: r['campaign_id'] as int?,
    direction: r['direction'] as String,
    body: (r['body'] as String?) ?? '',
    segments: (r['segments'] as int?) ?? 1,
    status: (r['status'] as String?) ?? 'pending',
    error: r['error'] as String?,
    createdAt: (r['created_at'] as int?) ?? 0,
    sentAt: r['sent_at'] as int?,
    deliveredAt: r['delivered_at'] as int?,
  );
}

class ThreadSummary {
  const ThreadSummary({
    required this.contactId,
    required this.kind,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.snippet,
    required this.name,
    required this.phoneLocal,
    required this.phoneE164,
    required this.contactStatus,
    required this.pinned,
    required this.archived,
    required this.draft,
  });

  final int contactId;
  final String kind;
  final int lastMessageAt;
  final int unreadCount;
  final String snippet;
  final String? name;
  final String phoneLocal;
  final String phoneE164;
  final String contactStatus;
  final bool pinned;
  final bool archived;

  /// A reply typed but not sent. Shown in place of the snippet, because what
  /// you were about to say matters more than what was last said to you.
  final String? draft;

  bool get hasDraft => draft != null && draft!.trim().isNotEmpty;

  String get display =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : phoneLocal;

  factory ThreadSummary.fromRow(Map<String, Object?> r) => ThreadSummary(
    contactId: r['contact_id'] as int,
    kind: (r['kind'] as String?) ?? 'campaign',
    lastMessageAt: (r['last_message_at'] as int?) ?? 0,
    unreadCount: (r['unread_count'] as int?) ?? 0,
    snippet: (r['snippet'] as String?) ?? '',
    name: r['name'] as String?,
    phoneLocal: (r['phone_local'] as String?) ?? '',
    phoneE164: (r['phone_e164'] as String?) ?? '',
    contactStatus: (r['status'] as String?) ?? '',
    pinned: (r['pinned'] as int? ?? 0) == 1,
    archived: (r['archived'] as int? ?? 0) == 1,
    draft: r['draft'] as String?,
  );
}

/// One message body that matched a search, with enough of its contact to be
/// listed and opened.
class MessageHit {
  const MessageHit({
    required this.messageId,
    required this.contactId,
    required this.body,
    required this.direction,
    required this.createdAt,
    required this.name,
    required this.phoneLocal,
  });

  final int messageId;
  final int contactId;
  final String body;
  final String direction;
  final int createdAt;
  final String? name;
  final String phoneLocal;

  bool get isInbound => direction == 'inbound';

  String get display =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : phoneLocal;

  factory MessageHit.fromRow(Map<String, Object?> r) => MessageHit(
    messageId: r['id'] as int,
    contactId: r['contact_id'] as int,
    body: (r['body'] as String?) ?? '',
    direction: (r['direction'] as String?) ?? 'inbound',
    createdAt: (r['created_at'] as int?) ?? 0,
    name: r['name'] as String?,
    phoneLocal: (r['phone_local'] as String?) ?? '',
  );
}

/// A personal message waiting for its moment.
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.contactId,
    required this.body,
    required this.sendAt,
  });

  final int id;
  final int contactId;
  final String body;
  final int sendAt;

  factory ScheduledMessage.fromRow(Map<String, Object?> r) => ScheduledMessage(
    id: r['id'] as int,
    contactId: r['contact_id'] as int,
    body: (r['body'] as String?) ?? '',
    sendAt: (r['send_at'] as int?) ?? 0,
  );
}

class NeedsReviewRow {
  const NeedsReviewRow({
    required this.id,
    required this.rawName,
    required this.rawPhone,
    required this.rawSource,
    required this.reason,
  });

  final int id;
  final String? rawName;
  final String? rawPhone;
  final String? rawSource;
  final String reason;

  factory NeedsReviewRow.fromRow(Map<String, Object?> r) => NeedsReviewRow(
    id: r['id'] as int,
    rawName: r['raw_name'] as String?,
    rawPhone: r['raw_phone'] as String?,
    rawSource: r['raw_source'] as String?,
    reason: (r['reason'] as String?) ?? '',
  );
}

class SimCard {
  const SimCard({
    required this.subscriptionId,
    required this.displayName,
    required this.carrierName,
    required this.number,
    required this.slotIndex,
  });

  final int subscriptionId;
  final String displayName;
  final String carrierName;
  final String number;
  final int slotIndex;

  String get label {
    final parts = <String>[displayName];
    if (carrierName.isNotEmpty && carrierName != displayName) {
      parts.add(carrierName);
    }
    if (number.isNotEmpty) parts.add(number);
    return parts.join(' · ');
  }

  factory SimCard.fromMap(Map<Object?, Object?> m) => SimCard(
    subscriptionId: (m['subscriptionId'] as num?)?.toInt() ?? -1,
    displayName: (m['displayName'] as String?) ?? 'SIM',
    carrierName: (m['carrierName'] as String?) ?? '',
    number: (m['number'] as String?) ?? '',
    slotIndex: (m['slotIndex'] as num?)?.toInt() ?? 0,
  );
}

class DefaultSmsInfo {
  const DefaultSmsInfo({
    required this.isDefault,
    required this.packageName,
    required this.label,
    required this.previousPackage,
    required this.previousLabel,
  });

  final bool isDefault;
  final String? packageName;
  final String? label;
  final String? previousPackage;
  final String? previousLabel;

  static const unknown = DefaultSmsInfo(
    isDefault: false,
    packageName: null,
    label: null,
    previousPackage: null,
    previousLabel: null,
  );

  factory DefaultSmsInfo.fromMap(Map<Object?, Object?> m) => DefaultSmsInfo(
    isDefault: (m['isDefault'] as bool?) ?? false,
    packageName: m['package'] as String?,
    label: m['label'] as String?,
    previousPackage: m['previousPackage'] as String?,
    previousLabel: m['previousLabel'] as String?,
  );
}

class CampaignProgress {
  const CampaignProgress({
    required this.campaignId,
    required this.batchId,
    required this.batchName,
    required this.total,
    required this.sent,
    required this.delivered,
    required this.failed,
    required this.replied,
    required this.remaining,
    required this.engineState,
    required this.template,
    required this.startedAt,
  });

  final int campaignId;
  final int batchId;
  final String batchName;
  final int total;
  final int sent;
  final int delivered;
  final int failed;
  final int replied;
  final int remaining;

  /// idle | running | paused — written by the native send service.
  final String engineState;
  final String template;
  final int startedAt;

  /// Contacts in this batch that the engine has finished with, one way or another.
  int get processed => total - remaining;

  double get fraction => total == 0 ? 0 : processed / total;

  bool get isRunning => engineState == 'running';
  bool get isPaused => engineState == 'paused';
}

class Stats {
  const Stats({
    required this.totalContacts,
    required this.notSent,
    required this.sent,
    required this.delivered,
    required this.replied,
    required this.failed,
    required this.doNotContact,
    required this.sentToday,
    required this.segmentsToday,
    required this.capCountsSegments,
    required this.dailyCap,
    required this.needsReview,
    required this.unread,
  });

  final int totalContacts;
  final int notSent;
  final int sent;
  final int delivered;
  final int replied;
  final int failed;
  final int doNotContact;
  final int sentToday;

  /// SMS segments, not messages — what the operator actually charged for.
  final int segmentsToday;
  final bool capCountsSegments;
  final int dailyCap;
  final int needsReview;
  final int unread;

  /// Everything that has left the phone at least once.
  int get reached => sent + delivered + replied;

  /// The figure the daily cap is actually enforced against.
  int get usedToday => capCountsSegments ? segmentsToday : sentToday;

  String get capUnit => capCountsSegments ? 'SMS' : 'messages';

  bool get capHit => usedToday >= dailyCap;

  double get progress => totalContacts == 0 ? 0 : reached / totalContacts;
}

/// A note. Deliberately plain: a title, a body, a tint and two timestamps.
///
/// Checklists are just lines that begin with "- " or "x " — no separate item
/// table, no sync of structure to text, and a note stays readable if it is
/// exported or read straight out of the database.
class Note {
  const Note({
    required this.id,
    required this.title,
    required this.body,
    required this.tint,
    required this.pinned,
    required this.contactId,
    required this.createdAt,
    required this.updatedAt,
    this.contactName,
    this.contactPhone,
  });

  final int id;
  final String title;
  final String body;
  final int tint;
  final bool pinned;

  /// The person this note is about, when it is about one. Null is the ordinary
  /// case — a note on the back of the hand, belonging to nobody.
  final int? contactId;

  /// Joined from the contact so a card can name them. A note that says only
  /// "belongs to somebody" answers the wrong question.
  final String? contactName;
  final String? contactPhone;
  final int createdAt;
  final int updatedAt;

  /// Who it is about, as it should be printed: their name, or their number.
  String? get about {
    if (contactId == null) return null;
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phone = contactPhone?.trim();
    return (phone == null || phone.isEmpty) ? null : phone;
  }

  bool get isEmpty => title.trim().isEmpty && body.trim().isEmpty;

  /// First line of the body, for a card that has no title.
  String get preview {
    for (final line in body.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return '';
  }

  static Note fromRow(Map<String, Object?> r) => Note(
    id: r['id'] as int,
    title: (r['title'] as String?) ?? '',
    body: (r['body'] as String?) ?? '',
    tint: (r['tint'] as int?) ?? 0,
    pinned: ((r['pinned'] as int?) ?? 0) == 1,
    contactId: r['contact_id'] as int?,
    contactName: r['contact_name'] as String?,
    contactPhone: r['contact_phone'] as String?,
    createdAt: (r['created_at'] as int?) ?? 0,
    updatedAt: (r['updated_at'] as int?) ?? 0,
  );
}

/// A sentence kept because it gets typed every day.
class Template {
  const Template({
    required this.id,
    required this.label,
    required this.body,
    required this.position,
  });

  final int id;
  final String label;
  final String body;
  final int position;

  /// What to call it in a list: the label if there is one, otherwise the
  /// opening words — which is usually enough to recognise it by.
  String get display {
    if (label.trim().isNotEmpty) return label.trim();
    final flat = body.replaceAll('\n', ' ').trim();
    return flat.length <= 42 ? flat : '${flat.substring(0, 42)}…';
  }

  factory Template.fromRow(Map<String, Object?> r) => Template(
    id: r['id'] as int,
    label: (r['label'] as String?) ?? '',
    body: (r['body'] as String?) ?? '',
    position: (r['position'] as int?) ?? 0,
  );
}

/// One entry from the phone's call log, read-only.
///
/// The type codes are Android's own (CallLog.Calls): 1 incoming, 2 outgoing,
/// 3 missed, 5 rejected. Anything else is treated as a plain call.
class CallEntry {
  const CallEntry({
    required this.type,
    required this.date,
    required this.durationSeconds,
  });

  final int type;
  final int date;
  final int durationSeconds;

  bool get isMissed => type == 3 || type == 5;
  bool get isOutgoing => type == 2;

  String get label => switch (type) {
    2 => 'Outgoing call',
    3 => 'Missed call',
    5 => 'Declined call',
    _ => 'Incoming call',
  };

  /// "4 min" / "32s" — empty for calls that never connected.
  String get length {
    if (durationSeconds <= 0) return '';
    if (durationSeconds < 60) return '${durationSeconds}s';
    return '${(durationSeconds + 30) ~/ 60} min';
  }
}

/// One row of the whole call log, number included — for the Calls screen.
class RecentCall {
  const RecentCall({required this.number, required this.entry});

  final String number;
  final CallEntry entry;
}

/// A viewing, a meeting, a call-back — something to be somewhere for.
class Appointment {
  const Appointment({
    required this.id,
    required this.contactId,
    required this.title,
    required this.place,
    required this.at,
    required this.remindAt,
    required this.done,
    required this.contactName,
    required this.contactPhone,
  });

  final int id;
  final int? contactId;
  final String title;
  final String? place;

  /// When it happens.
  final int at;

  /// When to be told about it — usually earlier than [at].
  final int remindAt;
  final bool done;

  /// Joined from the contact, so a list can name the person without a
  /// second query per row.
  final String? contactName;
  final String? contactPhone;

  String? get who {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phone = contactPhone?.trim();
    return (phone == null || phone.isEmpty) ? null : phone;
  }

  bool get isPast => at < DateTime.now().millisecondsSinceEpoch;

  factory Appointment.fromRow(Map<String, Object?> r) => Appointment(
    id: r['id'] as int,
    contactId: r['contact_id'] as int?,
    title: (r['title'] as String?) ?? '',
    place: r['place'] as String?,
    at: (r['at'] as int?) ?? 0,
    remindAt: (r['remind_at'] as int?) ?? 0,
    done: ((r['done'] as int?) ?? 0) == 1,
    contactName: r['name'] as String?,
    contactPhone: r['phone_local'] as String?,
  );
}

/// The stages a deal moves through. Stored as text, so a database browsed by
/// hand still reads like English.
class DealStage {
  static const newLead = 'new';
  static const contacted = 'contacted';
  static const viewing = 'viewing';
  static const negotiating = 'negotiating';
  static const won = 'won';
  static const lost = 'lost';

  /// Board order. Open stages first, then the two ways a deal ends.
  static const all = [newLead, contacted, viewing, negotiating, won, lost];

  /// The stages a deal is still alive in — what the pipeline card counts and
  /// what "going cold" watches.
  static const open = [newLead, contacted, viewing, negotiating];

  static bool isOpen(String stage) => open.contains(stage);

  static String label(String stage) => switch (stage) {
    newLead => 'New',
    contacted => 'Contacted',
    viewing => 'Viewing booked',
    negotiating => 'Negotiating',
    won => 'Won',
    lost => 'Lost',
    _ => stage,
  };
}

/// One thing being sold to one person: "Bole apartment, 3BR" for Dani,
/// moving new → contacted → viewing → negotiating → won or lost.
class Deal {
  const Deal({
    required this.id,
    required this.contactId,
    required this.title,
    required this.stage,
    required this.price,
    required this.stageChangedAt,
    required this.closedAt,
    required this.createdAt,
    this.contactName,
    this.contactPhone,
  });

  final int id;
  final int contactId;
  final String title;
  final String stage;

  /// In birr, or null when no figure has been put on it yet.
  final int? price;

  /// When it entered the current stage — "stuck for three weeks" reads from
  /// here.
  final int stageChangedAt;

  /// Set by won/lost only; reopening clears it.
  final int? closedAt;
  final int createdAt;

  /// Joined from the contact so a board card can name the person.
  final String? contactName;
  final String? contactPhone;

  bool get isOpen => DealStage.isOpen(stage);

  String get who {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return contactPhone?.trim() ?? '';
  }

  /// What the deal is about, or a stand-in when they never typed it.
  String get what => title.trim().isEmpty ? 'Deal' : title.trim();

  /// Whole days spent in the current stage.
  int get daysInStage {
    final ms = DateTime.now().millisecondsSinceEpoch - stageChangedAt;
    return ms < 0 ? 0 : ms ~/ Duration.millisecondsPerDay;
  }

  factory Deal.fromRow(Map<String, Object?> r) => Deal(
    id: r['id'] as int,
    contactId: r['contact_id'] as int,
    title: (r['title'] as String?) ?? '',
    stage: (r['stage'] as String?) ?? DealStage.newLead,
    price: r['price'] as int?,
    stageChangedAt: (r['stage_changed_at'] as int?) ?? 0,
    closedAt: r['closed_at'] as int?,
    createdAt: (r['created_at'] as int?) ?? 0,
    contactName: r['contact_name'] as String?,
    contactPhone: r['contact_phone'] as String?,
  );
}

/// A label a person wears: "buyer", "car", "hot".
class Tag {
  const Tag({required this.id, required this.name, this.count = 0});

  final int id;
  final String name;

  /// How many contacts wear it — joined in for lists, zero elsewhere.
  final int count;

  factory Tag.fromRow(Map<String, Object?> r) => Tag(
    id: r['id'] as int,
    name: (r['name'] as String?) ?? '',
    count: (r['count'] as int?) ?? 0,
  );
}

/// Somebody with a live deal who has not been talked to in a while. The
/// dashboard's "going cold" section is a list of these.
class ColdContact {
  const ColdContact({
    required this.contact,
    required this.deal,
    required this.lastTalkedAt,
  });

  final Contact contact;
  final Deal deal;

  /// The last call or personal message either way — campaign blasts do not
  /// count as talking. Zero when the app has never seen a touch.
  final int lastTalkedAt;

  /// Whole days of silence; -1 when there is nothing to measure from.
  int get daysQuiet {
    if (lastTalkedAt <= 0) return -1;
    final ms = DateTime.now().millisecondsSinceEpoch - lastTalkedAt;
    return ms < 0 ? 0 : ms ~/ Duration.millisecondsPerDay;
  }
}

/// One thing being brokered, remembering who brought it.
///
/// Deliberately not "car". The shelf started as a car shelf because that is
/// what the first user sells, but a broker who moves cars this year moves
/// houses the next, and the row — a title, some words, photos, who sent it,
/// whether it is gone — never cared which.
class Listing {
  const Listing({
    required this.id,
    required this.title,
    required this.body,
    required this.sourceContactId,
    required this.sourceText,
    required this.photos,
    required this.sold,
    required this.createdAt,
    required this.soldAt,
    this.sourceName,
    this.sourcePhone,
  });

  final int id;
  final String title;
  final String body;

  /// Who sent it, as a contact — or null when they only exist on Telegram.
  final int? sourceContactId;

  /// The sender as words, when they are not a contact: "@teddy_cars".
  final String? sourceText;

  /// Absolute paths of photos copied into the app's own storage.
  final List<String> photos;
  final bool sold;
  final int createdAt;
  final int? soldAt;

  /// Joined from the contact for lists.
  final String? sourceName;
  final String? sourcePhone;

  /// The public code that goes in the channel post caption. The row id is
  /// the number, so the code can never collide and survives everything —
  /// including the renames: the search accepts any letters in front, so a
  /// post captioned #AW047 or #TR047 still finds car 47.
  String get code => '#LF${id.toString().padLeft(3, '0')}';

  /// Who to ring: the contact's name, their number, or the free-text source.
  String get who {
    final name = sourceName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final phone = sourcePhone?.trim();
    if (phone != null && phone.isNotEmpty) return phone;
    final text = sourceText?.trim();
    if (text != null && text.isNotEmpty) return text;
    return 'Unknown sender';
  }

  String get what => title.trim().isEmpty ? 'Listing $code' : title.trim();

  factory Listing.fromRow(Map<String, Object?> r) => Listing(
    id: r['id'] as int,
    title: (r['title'] as String?) ?? '',
    body: (r['body'] as String?) ?? '',
    sourceContactId: r['source_contact_id'] as int?,
    sourceText: r['source_text'] as String?,
    photos: decodePhotoList(r['photos'] as String?),
    sold: ((r['sold'] as int?) ?? 0) == 1,
    createdAt: (r['created_at'] as int?) ?? 0,
    soldAt: r['sold_at'] as int?,
    sourceName: r['source_name'] as String?,
    sourcePhone: r['source_phone'] as String?,
  );

  /// Stored as a JSON array; anything unreadable is simply no photos, since
  /// a car card must never crash the shelf.
  static List<String> decodePhotoList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final parsed = jsonDecode(raw);
      if (parsed is List) return parsed.whereType<String>().toList();
    } catch (_) {}
    return const [];
  }
}

/// One message seen arriving in another messenger.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.app,
    required this.sender,
    required this.room,
    required this.body,
    required this.at,
    required this.contactId,
    required this.seen,
    this.contactName,
  });

  final int id;

  /// The package it arrived in — see [chatAppLabel].
  final String app;
  final String sender;

  /// The group's name, when it came from a group rather than one person.
  final String? room;
  final String body;
  final int at;

  /// Who the app thinks this is, when the name could be matched.
  final int? contactId;
  final bool seen;
  final String? contactName;

  String get appLabel => chatAppLabel(app);

  /// The name to print: the contact this was linked to, else the name the
  /// messenger showed.
  String get who {
    final name = contactName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return sender;
  }

  factory ChatMessage.fromRow(Map<String, Object?> r) => ChatMessage(
    id: r['id'] as int,
    app: (r['app'] as String?) ?? '',
    sender: (r['sender'] as String?) ?? '',
    room: r['room'] as String?,
    body: (r['body'] as String?) ?? '',
    at: (r['at'] as int?) ?? 0,
    contactId: r['contact_id'] as int?,
    seen: ((r['seen'] as int?) ?? 0) == 1,
    contactName: r['contact_name'] as String?,
  );
}

/// Package names to what a human calls them. Kept beside the same list in
/// `ChatApps.kt`; a package missing here simply prints itself.
String chatAppLabel(String package) => switch (package) {
  'com.whatsapp' => 'WhatsApp',
  'com.whatsapp.w4b' => 'WhatsApp Business',
  'org.telegram.messenger' => 'Telegram',
  'org.thunderdog.challegram' => 'Telegram X',
  'com.instagram.android' => 'Instagram',
  'com.facebook.orca' => 'Messenger',
  'com.viber.voip' => 'Viber',
  'com.imo.android.imoim' => 'imo',
  'org.thoughtcrime.securesms' => 'Signal',
  _ => package,
};

/// One line of a note body, classified for display.
///
/// `- something` is an open item, `x something` is a done one, anything else is
/// prose. Writing it in the text rather than in the schema means a checklist
/// survives being copied into a message or an export.
class NoteLine {
  const NoteLine(this.text, {this.checkable = false, this.done = false});

  final String text;
  final bool checkable;
  final bool done;

  static NoteLine parse(String raw) {
    final line = raw.trimRight();
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('- ')) {
      return NoteLine(trimmed.substring(2), checkable: true);
    }
    if (trimmed.startsWith('x ') || trimmed.startsWith('X ')) {
      return NoteLine(trimmed.substring(2), checkable: true, done: true);
    }
    return NoteLine(line);
  }

  /// The text form again, so toggling a box can be written straight back.
  String render() {
    if (!checkable) return text;
    return done ? 'x $text' : '- $text';
  }

  NoteLine toggled() =>
      NoteLine(text, checkable: checkable, done: checkable ? !done : done);
}

/// How many messages left the phone on one day.
class DayCount {
  const DayCount(this.day, this.messages, this.replies);

  final DateTime day;
  final int messages;
  final int replies;
}

/// The last week, for the dashboard's chart and its delta chips.
///
/// Every figure here is counted from the message table rather than stored, so
/// there is no running total to drift out of step with what was actually sent.
class Trend {
  const Trend(this.days);

  final List<DayCount> days;

  int get today => days.isEmpty ? 0 : days.last.messages;
  int get yesterday => days.length < 2 ? 0 : days[days.length - 2].messages;
  int get repliesToday => days.isEmpty ? 0 : days.last.replies;

  int get peak => days.fold(0, (m, d) => d.messages > m ? d.messages : m);
  int get total => days.fold(0, (s, d) => s + d.messages);

  /// Change against yesterday, as a percentage. Null when there is nothing to
  /// compare against — a first day is not a hundred per cent rise.
  double? get change {
    if (days.length < 2 || yesterday == 0) return null;
    return (today - yesterday) / yesterday * 100;
  }
}

/// What the operator has actually counted, as opposed to how many people were
/// messaged.
///
/// The distinction is the whole point of this screen: one message is one row
/// here and one *or more* SMS on the network. A campaign in Amharic costs about
/// three times what the same campaign costs in English, and the only place that
/// shows up is the bill.
class Usage {
  const Usage({
    required this.messages,
    required this.segments,
    required this.latinMessages,
    required this.latinSegments,
    required this.amharicMessages,
    required this.amharicSegments,
    required this.today,
    required this.week,
    required this.month,
    required this.bundle,
  });

  /// Messages sent, all time.
  final int messages;

  /// SMS those messages cost, all time.
  final int segments;

  final int latinMessages;
  final int latinSegments;
  final int amharicMessages;
  final int amharicSegments;

  /// Segments in the last day, seven days and thirty days.
  final int today;
  final int week;
  final int month;

  /// The size of the package the user told us about, or zero if they have not.
  final int bundle;

  int get remaining => bundle == 0 ? 0 : (bundle - segments).clamp(0, bundle);

  double get bundleUsed =>
      bundle == 0 ? 0 : (segments / bundle).clamp(0.0, 1.0);

  /// Average SMS per message. The number that explains a bill.
  double get costPerMessage => messages == 0 ? 0 : segments / messages;

  double get amharicCost =>
      amharicMessages == 0 ? 0 : amharicSegments / amharicMessages;

  double get latinCost =>
      latinMessages == 0 ? 0 : latinSegments / latinMessages;

  /// Share of the total cost that Amharic accounts for.
  double get amharicShare => segments == 0 ? 0 : amharicSegments / segments;
}
