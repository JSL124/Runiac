import { describe, it } from 'node:test';
import { assertFails } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, setDoc, updateDoc } from 'firebase/firestore';

import { dbFor, seed, seedUser, unauthenticatedDb } from './support/firestore_rules_test_support.mjs';

const subscriberDoc = {
  emailLower: 'runner@example.com',
  status: 'pending',
  source: 'website_hero',
  consentAt: 1,
  confirmTokenHash: 'hash',
  confirmTokenExpiresAt: 2,
  unsubscribeTokenHash: 'hash',
  ipHash: 'iphash',
  sendFailureCount: 0,
  createdAt: 1,
  updatedAt: 1,
};

const campaignDoc = {
  subject: 'Runiac monthly update',
  bodyMarkdown: 'Hello runners.',
  status: 'draft',
  createdBy: 'admin',
  createdAt: 1,
};

const deliveryDoc = {
  status: 'sent',
  mailDocId: 'mail1',
  createdAt: 1,
};

const rateLimitDoc = {
  windowStart: 1,
  count: 1,
};

const mailDoc = {
  to: 'runner@example.com',
  message: {
    subject: 'Hello',
    html: '<p>Hello</p>',
    text: 'Hello',
  },
};

describe('backend-owned newsletter collections', () => {
  it('denies an authenticated client every direct read/write on newsletterSubscribers, including seeded docs', async () => {
    await seedUser('alice', 'basic');
    await seed('newsletterSubscribers/sub1', subscriberDoc);

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'newsletterSubscribers/sub1')));
    await assertFails(getDocs(collection(alice, 'newsletterSubscribers')));
    await assertFails(setDoc(doc(alice, 'newsletterSubscribers/sub2'), subscriberDoc));
    await assertFails(updateDoc(doc(alice, 'newsletterSubscribers/sub1'), { status: 'confirmed' }));
    await assertFails(deleteDoc(doc(alice, 'newsletterSubscribers/sub1')));
  });

  it('denies an unauthenticated client every direct read/write on newsletterSubscribers', async () => {
    await seed('newsletterSubscribers/sub1', subscriberDoc);

    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(anon, 'newsletterSubscribers/sub1')));
    await assertFails(getDocs(collection(anon, 'newsletterSubscribers')));
    await assertFails(setDoc(doc(anon, 'newsletterSubscribers/sub2'), subscriberDoc));
    await assertFails(updateDoc(doc(anon, 'newsletterSubscribers/sub1'), { status: 'confirmed' }));
    await assertFails(deleteDoc(doc(anon, 'newsletterSubscribers/sub1')));
  });

  it('denies an authenticated client every direct read/write on newsletterCampaigns and its deliveries subcollection', async () => {
    await seedUser('alice', 'basic');
    await seed('newsletterCampaigns/camp1', campaignDoc);
    await seed('newsletterCampaigns/camp1/deliveries/sub1', deliveryDoc);

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'newsletterCampaigns/camp1')));
    await assertFails(getDocs(collection(alice, 'newsletterCampaigns')));
    await assertFails(setDoc(doc(alice, 'newsletterCampaigns/camp2'), campaignDoc));
    await assertFails(updateDoc(doc(alice, 'newsletterCampaigns/camp1'), { status: 'queued' }));
    await assertFails(deleteDoc(doc(alice, 'newsletterCampaigns/camp1')));

    await assertFails(getDoc(doc(alice, 'newsletterCampaigns/camp1/deliveries/sub1')));
    await assertFails(getDocs(collection(alice, 'newsletterCampaigns/camp1/deliveries')));
    await assertFails(setDoc(doc(alice, 'newsletterCampaigns/camp1/deliveries/sub2'), deliveryDoc));
    await assertFails(updateDoc(doc(alice, 'newsletterCampaigns/camp1/deliveries/sub1'), { status: 'failed' }));
    await assertFails(deleteDoc(doc(alice, 'newsletterCampaigns/camp1/deliveries/sub1')));
  });

  it('denies an unauthenticated client every direct read/write on newsletterCampaigns and its deliveries subcollection', async () => {
    await seed('newsletterCampaigns/camp1', campaignDoc);
    await seed('newsletterCampaigns/camp1/deliveries/sub1', deliveryDoc);

    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(anon, 'newsletterCampaigns/camp1')));
    await assertFails(getDocs(collection(anon, 'newsletterCampaigns')));
    await assertFails(setDoc(doc(anon, 'newsletterCampaigns/camp2'), campaignDoc));
    await assertFails(updateDoc(doc(anon, 'newsletterCampaigns/camp1'), { status: 'queued' }));
    await assertFails(deleteDoc(doc(anon, 'newsletterCampaigns/camp1')));

    await assertFails(getDoc(doc(anon, 'newsletterCampaigns/camp1/deliveries/sub1')));
    await assertFails(getDocs(collection(anon, 'newsletterCampaigns/camp1/deliveries')));
    await assertFails(setDoc(doc(anon, 'newsletterCampaigns/camp1/deliveries/sub2'), deliveryDoc));
    await assertFails(updateDoc(doc(anon, 'newsletterCampaigns/camp1/deliveries/sub1'), { status: 'failed' }));
    await assertFails(deleteDoc(doc(anon, 'newsletterCampaigns/camp1/deliveries/sub1')));
  });

  it('denies an authenticated client every direct read/write on newsletterRateLimits', async () => {
    await seedUser('alice', 'basic');
    await seed('newsletterRateLimits/iphash1', rateLimitDoc);

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'newsletterRateLimits/iphash1')));
    await assertFails(getDocs(collection(alice, 'newsletterRateLimits')));
    await assertFails(setDoc(doc(alice, 'newsletterRateLimits/iphash2'), rateLimitDoc));
    await assertFails(updateDoc(doc(alice, 'newsletterRateLimits/iphash1'), { count: 2 }));
    await assertFails(deleteDoc(doc(alice, 'newsletterRateLimits/iphash1')));
  });

  it('denies an unauthenticated client every direct read/write on newsletterRateLimits', async () => {
    await seed('newsletterRateLimits/iphash1', rateLimitDoc);

    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(anon, 'newsletterRateLimits/iphash1')));
    await assertFails(getDocs(collection(anon, 'newsletterRateLimits')));
    await assertFails(setDoc(doc(anon, 'newsletterRateLimits/iphash2'), rateLimitDoc));
    await assertFails(updateDoc(doc(anon, 'newsletterRateLimits/iphash1'), { count: 2 }));
    await assertFails(deleteDoc(doc(anon, 'newsletterRateLimits/iphash1')));
  });

  it('denies an authenticated client every direct read/write on mail', async () => {
    await seedUser('alice', 'basic');
    await seed('mail/mail1', mailDoc);

    const alice = dbFor('alice');

    await assertFails(getDoc(doc(alice, 'mail/mail1')));
    await assertFails(getDocs(collection(alice, 'mail')));
    await assertFails(setDoc(doc(alice, 'mail/mail2'), mailDoc));
    await assertFails(updateDoc(doc(alice, 'mail/mail1'), { to: 'other@example.com' }));
    await assertFails(deleteDoc(doc(alice, 'mail/mail1')));
  });

  it('denies an unauthenticated client every direct read/write on mail', async () => {
    await seed('mail/mail1', mailDoc);

    const anon = unauthenticatedDb();

    await assertFails(getDoc(doc(anon, 'mail/mail1')));
    await assertFails(getDocs(collection(anon, 'mail')));
    await assertFails(setDoc(doc(anon, 'mail/mail2'), mailDoc));
    await assertFails(updateDoc(doc(anon, 'mail/mail1'), { to: 'other@example.com' }));
    await assertFails(deleteDoc(doc(anon, 'mail/mail1')));
  });
});
