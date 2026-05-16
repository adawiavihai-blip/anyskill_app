// Booking summary sheet — H.3 (§86, 2026-05-14).
//
// Extracted from `_showBookingSummary` (508 LOC) on
// expert_profile_screen.dart. Lives as a `part of` so the StatefulBuilder
// can still close over the State's mutable fields (_bookingReqValues,
// _selectedDog, _petStayEndDate, _serviceSchema, _processEscrowPayment,
// _selectedDay, _selectedTimeSlot, _selectedServiceIndex). Single
// top-level function `_libShowBookingSummary(state, context, data, price,
// addOns, selectedAddOns)` — state class keeps a thin wrapper.

part of '../../expert_profile_screen.dart';

/// Show the booking summary bottom sheet with optional add-ons.
///
/// The sheet renders either the summary form (default) OR the success
/// view (after [_processEscrowPayment] succeeds). The success view's
/// "Done" button is the ONLY place that pops the sheet — decoupling
/// Navigator.pop from the Firestore Promise chain prevents the Web
/// "converted Future" exception.
void _libShowBookingSummary(
  _ExpertProfileScreenState state,
  BuildContext context,
  Map<String, dynamic> data,
  double price, {
  List<AddOn> addOns = const [],
  Set<int> selectedAddOns = const {},
}) {
  final l10n = AppLocalizations.of(context);
  final isDemo = data['isDemo'] == true;
  final dateStr = state._selectedDay != null
      ? '${state._selectedDay!.day}/${state._selectedDay!.month}/${state._selectedDay!.year}'
      : '';
  final svcTitles = [
    l10n.serviceSingleLesson,
    l10n.serviceExtendedLesson,
    l10n.serviceFullSession,
  ];
  final svcTitle = svcTitles[state._selectedServiceIndex.clamp(0, 2)];

  final policy = data['cancellationPolicy'] as String? ?? 'flexible';

  final dlDt = CancellationPolicyService.deadline(
    policy: policy,
    appointmentDate: state._selectedDay,
    timeSlot: state._selectedTimeSlot,
  );
  final dlStr = dlDt != null
      ? '${dlDt.day}/${dlDt.month} ${dlDt.hour.toString().padLeft(2, '0')}:${dlDt.minute.toString().padLeft(2, '0')}'
      : null;
  final penaltyPct =
      (CancellationPolicyService.penaltyFraction(policy) * 100).toInt();

  bool sheetBusy = false;
  bool isSuccess = false;

  final reqValues = Map<String, dynamic>.from(state._bookingReqValues);

  final bool isPetStayBooking =
      state._serviceSchema.walkTracking || state._serviceSchema.dailyProof;
  final bool isPensionBooking = state._serviceSchema.dailyProof;
  DogProfile? selectedDog = state._selectedDog;

  DateTime? petStayEnd = state._petStayEndDate ??
      (isPensionBooking && state._selectedDay != null
          ? state._selectedDay!.add(const Duration(days: 1))
          : null);

  int nights = (isPensionBooking &&
          state._selectedDay != null &&
          petStayEnd != null)
      ? petStayEnd.difference(state._selectedDay!).inDays.clamp(1, 30)
      : 1;

  double effectivePrice() =>
      (isPensionBooking ? price * nights : price).toDouble();

  bool requirementsSatisfied() {
    if (isPensionBooking) return true;
    for (final r in state._serviceSchema.bookingRequirements) {
      if (!r.required) continue;
      final v = reqValues[r.id];
      if (v == null) return false;
      if (v is String && v.trim().isEmpty) return false;
      if (v is num && v == 0) return false;
    }
    return true;
  }

  bool endDateOk() {
    if (!isPensionBooking) return true;
    if (state._selectedDay == null || petStayEnd == null) return false;
    return !petStayEnd!.isBefore(state._selectedDay!);
  }

  bool canConfirm() =>
      requirementsSatisfied() &&
      (!isPetStayBooking || selectedDog != null) &&
      endDateOk();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    builder: (sheetCtx) => StatefulBuilder(
      builder: (sheetCtx, setSheetState) {
        if (isSuccess) {
          return BookingSuccessView(isDemo: isDemo);
        }

        final bottomInset = MediaQuery.of(sheetCtx).viewInsets.bottom;
        final screenH = MediaQuery.of(sheetCtx).size.height;
        return AbsorbPointer(
          absorbing: sheetBusy,
          child: Container(
            constraints: BoxConstraints(maxHeight: screenH * 0.92),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomInset),
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              l10n.expertBookingSummaryTitle,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$svcTitle • $dateStr ${state._selectedTimeSlot ?? ''}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _kPurpleSoft,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.lock_rounded,
                          color: _kPurple,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        state._summaryRow(l10n.expertSummaryRowService, svcTitle),
                        state._summaryRow(l10n.expertSummaryRowDate, dateStr),
                        state._summaryRow(
                          l10n.expertSummaryRowTime,
                          state._selectedTimeSlot ?? '—',
                        ),
                        state._summaryRow(
                          l10n.expertSummaryRowPrice,
                          '₪${(price - selectedAddOns.fold<double>(0.0, (s, i) => s + (i < addOns.length ? addOns[i].price : 0.0))).toStringAsFixed(0)}',
                        ),
                        for (final i in selectedAddOns)
                          if (i < addOns.length)
                            state._summaryRow(
                              '+ ${addOns[i].title}',
                              '+₪${addOns[i].price.toStringAsFixed(0)}',
                              isAddOn: true,
                            ),
                        state._summaryRow(
                          l10n.expertSummaryRowProtection,
                          l10n.expertSummaryRowIncluded,
                          isGreen: true,
                        ),
                        if (state._serviceSchema.priceLocked)
                          state._summaryRow(
                            '🔒 מחיר נעול',
                            AppLocalizations.of(context).expPriceAfterPhotos,
                            isGreen: true,
                          ),
                        if (state._serviceSchema.depositPercent > 0)
                          state._summaryRow(
                            AppLocalizations.of(context).expDeposit,
                            '₪${(price * state._serviceSchema.depositPercent / 100).toStringAsFixed(0)} '
                                '(${state._serviceSchema.depositPercent.toStringAsFixed(0)}%)',
                          ),
                        if (isPensionBooking) ...[
                          state._summaryRow(
                            AppLocalizations.of(context).expNights,
                            '$nights × ₪${price.toStringAsFixed(0)}',
                          ),
                        ],
                        const Divider(height: 16),
                        state._summaryRow(
                          l10n.expertSummaryRowTotal,
                          '₪${effectivePrice().toStringAsFixed(0)}',
                          isBold: true,
                        ),
                      ],
                    ),
                  ),
                  if (isPensionBooking) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          14, 10, 14, 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.nights_stay_rounded,
                              color: Color(0xFF6366F1),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context).expNightsCount,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          _NightStepperButton(
                            icon: Icons.remove_rounded,
                            onTap: nights > 1 && state._selectedDay != null
                                ? () {
                                    setSheetState(() {
                                      nights -= 1;
                                      petStayEnd = state._selectedDay!
                                          .add(Duration(days: nights));
                                      state._petStayEndDate = petStayEnd;
                                    });
                                  }
                                : null,
                          ),
                          Container(
                            width: 44,
                            alignment: Alignment.center,
                            child: Text(
                              '$nights',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFF1A1A2E),
                              ),
                            ),
                          ),
                          _NightStepperButton(
                            icon: Icons.add_rounded,
                            onTap: nights < 30 && state._selectedDay != null
                                ? () {
                                    setSheetState(() {
                                      nights += 1;
                                      petStayEnd = state._selectedDay!
                                          .add(Duration(days: nights));
                                      state._petStayEndDate = petStayEnd;
                                    });
                                  }
                                : null,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        final firstAllowed =
                            state._selectedDay ?? DateTime.now();
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: petStayEnd ??
                              firstAllowed.add(const Duration(days: 1)),
                          firstDate: firstAllowed,
                          lastDate:
                              firstAllowed.add(const Duration(days: 180)),
                        );
                        if (picked != null) {
                          setSheetState(() {
                            petStayEnd = picked;
                            state._petStayEndDate = picked;
                            nights = picked
                                .difference(state._selectedDay ?? picked)
                                .inDays
                                .clamp(1, 30);
                          });
                        }
                      },
                      child: Container(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                            14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: endDateOk()
                                ? const Color(0xFFE5E7EB)
                                : const Color(0xFFEF4444),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(
                                Icons.date_range_rounded,
                                color: Color(0xFF6366F1),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    AppLocalizations.of(context).expEndDate,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                      color: Color(0xFF1A1A2E),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    petStayEnd == null
                                        ? AppLocalizations.of(context)
                                            .expSelectDate
                                        : '${petStayEnd!.day}/${petStayEnd!.month}/${petStayEnd!.year}'
                                            ' · ${state._selectedDay != null ? petStayEnd!.difference(state._selectedDay!).inDays : 0} ${AppLocalizations.of(context).expNights}',
                                    style: const TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(
                              Icons.chevron_left_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (isPetStayBooking) ...[
                    const SizedBox(height: 16),
                    DogPickerSection(
                      selected: selectedDog,
                      onChanged: (d) =>
                          setSheetState(() => selectedDog = d),
                    ),
                  ],
                  if (!isPensionBooking &&
                      state._serviceSchema.bookingRequirements.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    BookingRequirementsForm(
                      requirements: state._serviceSchema.bookingRequirements,
                      initialValues: reqValues,
                      onChanged: (vals) => setSheetState(() {
                        reqValues
                          ..clear()
                          ..addAll(vals);
                      }),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFFCC02), width: 1),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: Color(0xFF856404),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            dlStr != null
                                ? l10n.expertCancellationNotice(
                                    CancellationPolicyService.label(policy),
                                    dlStr,
                                    penaltyPct.toString())
                                : l10n.expertCancellationNoDeadline(
                                    CancellationPolicyService.label(policy),
                                    CancellationPolicyService.description(
                                        policy)),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF856404),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (!requirementsSatisfied()) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCD34D)),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: Color(0xFF92400E),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context).expMustFillAll,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF92400E),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  PrimaryCTA(
                    label: l10n.expertConfirmPaymentButton,
                    icon: Icons.lock_rounded,
                    variant: PrimaryCTAVariant.primary,
                    loading: sheetBusy,
                    height: 54,
                    semanticHint:
                        'Escrows the booking total until job is approved',
                    onPressed: !canConfirm()
                        ? null
                        : () async {
                            setSheetState(() => sheetBusy = true);
                            state._bookingReqValues
                              ..clear()
                              ..addAll(reqValues);
                            state._selectedDog = selectedDog;
                            final ok = await state._processEscrowPayment(
                              context,
                              effectivePrice(),
                              policy,
                              isDemo: isDemo,
                            );
                            if (ok) {
                              setSheetState(() => isSuccess = true);
                            } else {
                              setSheetState(() => sheetBusy = false);
                            }
                          },
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'AnySkill v$appVersion',
                    style: TextStyle(fontSize: 10, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
