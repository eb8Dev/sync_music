const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const { v4: uuidv4 } = require("uuid");

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
  cors: { origin: "*" }
});

// In-memory party store
const parties = new Map();

// ---- Models ----
function createParty(hostId) {
  return {
    id: uuidv4().slice(0, 6).toUpperCase(),
    hostId,
    queue: [],
    currentIndex: 0,
    isPlaying: false,
    startedAt: null,
    createdAt: Date.now(),
    lastActiveAt: Date.now()
  };
}

// ---- Helpers ----
function getPartyOrError(socket, partyId) {
  const party = parties.get(partyId);
  if (!party) {
    socket.emit("ERROR", "Party not found");
    return null;
  }
  party.lastActiveAt = Date.now();
  return party;
}

// ---- Socket Logic ----
io.on("connection", (socket) => {
  console.log("Connected:", socket.id);

  // ---------------- CREATE PARTY ----------------
  socket.on("CREATE_PARTY", (data) => {
    const party = createParty(socket.id);
    parties.set(party.id, party);

    socket.join(party.id);

    socket.emit("PARTY_STATE", {
      ...party,
      isHost: true
    });

    console.log("Party created:", party.id, "Host:", socket.id);
  });

  // ---------------- JOIN PARTY ----------------
  socket.on("JOIN_PARTY", (partyId) => {
    const party = getPartyOrError(socket, partyId);
    if (!party) return;

    socket.join(partyId);

    socket.emit("PARTY_STATE", {
      ...party,
      isHost: false
    });

    io.to(partyId).emit("INFO", "Someone joined the party");
    console.log("User joined party:", partyId, socket.id);
  });

  // ---------------- HOST RECLAIM ----------------
  socket.on("RECONNECT_AS_HOST", ({ partyId }) => {
    const party = parties.get(partyId);
    if (!party) return;

    console.log("Host reclaimed party:", partyId, "New host:", socket.id);
    party.hostId = socket.id;
    socket.join(partyId);
  });

  // ---------------- ADD TRACK ----------------
  socket.on("ADD_TRACK", ({ partyId, track }) => {
    const party = getPartyOrError(socket, partyId);
    if (!party) return;

    const newTrack = {
      id: uuidv4(),
      url: track.url,
      title: track.title || track.url,
      addedBy: track.addedBy || "Guest", // Use provided name!
      addedAt: Date.now()
    };

    party.queue.push(newTrack);

    io.to(partyId).emit("QUEUE_UPDATED", party.queue);
    console.log("Track added:", newTrack.title, "Party:", partyId);
  });

  // ---------------- PLAY (HOST ONLY) ----------------
  socket.on("PLAY", ({ partyId }) => {
    const party = getPartyOrError(socket, partyId);
    if (!party || socket.id !== party.hostId) return;

    if (party.queue.length === 0) return;

    party.isPlaying = true;
    party.startedAt = Date.now();

    io.to(partyId).emit("PLAYBACK_UPDATE", {
      isPlaying: true,
      startedAt: party.startedAt,
      currentIndex: party.currentIndex
    });
  });

  // ---------------- PAUSE (HOST ONLY) ----------------
  socket.on("PAUSE", ({ partyId }) => {
    const party = getPartyOrError(socket, partyId);
    if (!party || socket.id !== party.hostId) return;

    party.isPlaying = false;

    io.to(partyId).emit("PLAYBACK_UPDATE", {
      isPlaying: false
    });
  });

  // ---------------- TRACK ENDED (HOST ONLY) ----------------
  socket.on("TRACK_ENDED", ({ partyId }) => {
    const party = getPartyOrError(socket, partyId);
    if (!party || socket.id !== party.hostId) return;

    party.currentIndex++;

    if (party.currentIndex >= party.queue.length) {
      party.isPlaying = false;
      party.currentIndex = 0;
      io.to(partyId).emit("PLAYBACK_UPDATE", { isPlaying: false });
    } else {
      party.isPlaying = true;
      party.startedAt = Date.now();
      io.to(partyId).emit("PLAYBACK_UPDATE", {
        isPlaying: true,
        startedAt: party.startedAt,
        currentIndex: party.currentIndex
      });
    }
  });

  socket.on("END_PARTY", ({ partyId }) => {
    const party = parties.get(partyId);
    if (!party) return;

    // Only host can end party
    if (party.hostId !== socket.id) return;

    // Notify everyone
    io.to(partyId).emit("PARTY_ENDED", {
      message: "The host has ended the party.",
    });

    // Kick everyone out of the room
    const room = io.sockets.adapter.rooms.get(partyId);
    if (room) {
      for (const socketId of room) {
        const s = io.sockets.sockets.get(socketId);
        s?.leave(partyId);
      }
    }

    // Delete party
    parties.delete(partyId);

    console.log("Party ended:", partyId);
  });
  // ---------------- DISCONNECT ----------------
  socket.on("disconnect", () => {
    console.log("Disconnected:", socket.id);
    // Kept graceful disconnect (no auto-delete)
  });
});

// ---------------- SYNC LOOP ----------------
setInterval(() => {
  const now = Date.now();
  for (const [id, party] of parties) {
    if (party.isPlaying) {
      io.to(party.id).emit("SYNC", {
        serverTime: now,
        startedAt: party.startedAt,
        currentIndex: party.currentIndex
      });
    }
    // Auto-delete after 24h
    if (now - party.createdAt > 24 * 60 * 60 * 1000) {
      parties.delete(id);
    }
  }
}, 5000);

const PORT = process.env.PORT || 3000;
server.listen(PORT, () => {
  console.log("Server running on port", PORT);
});
