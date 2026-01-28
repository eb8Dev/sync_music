import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sync_music/providers/explore_provider.dart';
import 'package:sync_music/providers/party_provider.dart';
import 'package:sync_music/providers/user_provider.dart';
import 'package:sync_music/widgets/glass_card.dart';

class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exploreState = ref.watch(exploreProvider);
    final partyMeta = ref.watch(partyProvider);
    final userState = ref.watch(userProvider);
    final theme = Theme.of(context);

    void fetchParties() {
      ref.read(exploreProvider.notifier).fetchParties();
    }

    void joinParty(String partyId) {
      if (partyId == partyMeta.lastPartyId && partyMeta.isHost) {
        ref
            .read(partyProvider.notifier)
            .reconnectAsHost(
              partyId: partyId,
              username: userState.username,
              avatar: userState.avatar,
            );
      } else {
        ref
            .read(partyProvider.notifier)
            .joinParty(
              partyId: partyId,
              username: userState.username,
              avatar: userState.avatar,
            );
      }
      Navigator.pop(context);
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text(
          "EXPLORE",
          style: TextStyle(letterSpacing: 1.4, fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            splashRadius: 20,
            icon: const Icon(Icons.refresh_rounded),
            onPressed: fetchParties,
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
          ),
        ),
        child: SafeArea(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: exploreState.isLoading
                ? _LoadingState(theme: theme)
                : exploreState.publicParties.isEmpty
                ? _EmptyState(onRefresh: fetchParties)
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: exploreState.publicParties.length,
                    itemBuilder: (context, index) {
                      final party = exploreState.publicParties[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GlassCard(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => joinParty(party['id']),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                // ---- AVATAR ----
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: [
                                        theme.primaryColor.withOpacity(0.8),
                                        theme.primaryColor.withOpacity(0.4),
                                      ],
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.music_note_rounded,
                                    color: Colors.white,
                                  ),
                                ),

                                const SizedBox(width: 14),

                                // ---- INFO ----
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        party['name'] ?? "Music Party",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 15,
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        party['nowPlaying'] ??
                                            "Nothing playing",
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.6),
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 12),

                                // ---- META ----
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: theme.primaryColor.withOpacity(
                                          0.15,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.people_rounded,
                                            size: 12,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            "${party['memberCount']}",
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Icon(
                                      Icons.arrow_forward_ios_rounded,
                                      size: 14,
                                      color: Colors.white.withOpacity(0.3),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------

class _LoadingState extends StatelessWidget {
  const _LoadingState({required ThemeData theme});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: GlassCard(
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Avatar placeholder
                  _ShimmerBox(
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(24),
                  ),

                  const SizedBox(width: 14),

                  // Text placeholders
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        _ShimmerLine(widthFactor: 0.6),
                        SizedBox(height: 8),
                        _ShimmerLine(widthFactor: 0.4),
                      ],
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Meta placeholder
                  _ShimmerBox(
                    width: 42,
                    height: 18,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ShimmerLine extends StatelessWidget {
  final double widthFactor;
  const _ShimmerLine({required this.widthFactor});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: const _ShimmerBox(
        height: 12,
        borderRadius: BorderRadius.all(Radius.circular(6)),
      ),
    );
  }
}

class _ShimmerBox extends StatefulWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;

  const _ShimmerBox({
    this.width = double.infinity,
    required this.height,
    required this.borderRadius,
  });

  @override
  State<_ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<_ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withOpacity(0.06),
                Colors.white.withOpacity(0.14),
                Colors.white.withOpacity(0.06),
              ],
              stops: const [0.25, 0.5, 0.75],
              transform: _SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.08),
              borderRadius: widget.borderRadius,
            ),
          ),
        );
      },
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  final double slidePercent;
  const _SlidingGradientTransform({required this.slidePercent});

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0,
      0,
    );
  }
}

// ------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  const _EmptyState({required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.queue_music_rounded,
            size: 64,
            color: Colors.white.withOpacity(0.25),
          ),
          const SizedBox(height: 16),
          Text(
            "No public parties right now",
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Start one and invite your friends 🎶",
            style: TextStyle(
              color: Colors.white.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text("Refresh"),
          ),
        ],
      ),
    );
  }
}
