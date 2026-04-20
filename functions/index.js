const functions = require('firebase-functions');
const admin = require('firebase-admin');
const axios = require('axios');

admin.initializeApp();

exports.sendChatNotification = functions.firestore
    .document('chats/{chatId}/messages/{messageId}')
    .onCreate(async (snap, context) => {
        const message = snap.data();
        const chatId = context.params.chatId;
        
        try {
            const chatRef = snap.ref.parent.parent;
            const chatDoc = await chatRef.get();
            
            if (!chatDoc.exists) return;
            
            const chatData = chatDoc.data();
            const participants = (chatData.participants || []).map((id) => String(id));
            const senderId = String(message.senderId || '').trim();
            if (!senderId) return;

            const receiverId = participants.find((id) => id !== senderId);
            if (!receiverId) return;

            const receiverIdInt = Number.parseInt(receiverId, 10);
            const senderIdInt = Number.parseInt(senderId, 10);
            if (Number.isNaN(receiverIdInt) || Number.isNaN(senderIdInt)) {
                console.error('ID chat non numerici:', { receiverId, senderId, chatId });
                return;
            }
            
            // Chiama il tuo backend Hetzner
            const backendUrl = process.env.BACKEND_URL;
            const apiKey = process.env.CHAT_NOTIFICATION_API_KEY || process.env.BACKEND_API_KEY;
            if (!backendUrl || !apiKey) {
                console.error('Config mancante: BACKEND_URL/CHAT_NOTIFICATION_API_KEY');
                return;
            }
            
            await axios.post(`${backendUrl}/api/push/chat-notification`, {
                receiver_id: receiverIdInt,
                sender_id: senderIdInt,
                sender_name: message.senderName || chatData.lastSenderName || 'Utente',
                message_text: message.text,
                offer_id: parseInt(chatData.offerId),
                chat_id: chatId
            }, {
                headers: { 'Authorization': `Bearer ${apiKey}` }
            });
            
        } catch (error) {
            console.error('Errore notifica chat:', error);
        }
    });
