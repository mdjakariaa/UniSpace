-- ============================================================
-- UniSpace — Seed Data (Sample Rooms)
-- Run AFTER 001 and 002
-- ============================================================

INSERT INTO public.rooms (name, building, floor, total_seats, available_seats, facilities, status, rating) VALUES
  ('Room A-101', 'Academic Building A', 1, 30, 30, ARRAY['WiFi', 'Projector', 'Whiteboard', 'AC'], 'available', 4.5),
  ('Room A-205', 'Academic Building A', 2, 20, 20, ARRAY['WiFi', 'Whiteboard', 'AC'], 'available', 4.2),
  ('Room A-310', 'Academic Building A', 3, 15, 15, ARRAY['WiFi', 'Power Outlets', 'AC'], 'available', 3.8),
  ('Room B-102', 'Library Building B', 1, 40, 40, ARRAY['WiFi', 'Projector', 'Whiteboard', 'AC', 'Sound System'], 'available', 4.8),
  ('Room B-201', 'Library Building B', 2, 25, 25, ARRAY['WiFi', 'Whiteboard', 'Power Outlets'], 'available', 4.0),
  ('Room C-101', 'Science Block C', 1, 35, 35, ARRAY['WiFi', 'Projector', 'Lab Equipment', 'AC'], 'available', 4.6),
  ('Room C-203', 'Science Block C', 2, 18, 18, ARRAY['WiFi', 'Whiteboard', 'AC'], 'available', 3.9),
  ('Room D-101', 'Engineering Block D', 1, 50, 50, ARRAY['WiFi', 'Projector', 'Whiteboard', 'AC', 'Computers'], 'available', 4.7),
  ('Room D-302', 'Engineering Block D', 3, 12, 12, ARRAY['WiFi', 'Power Outlets'], 'available', 3.5),
  ('Room E-101', 'Student Center E', 1, 60, 60, ARRAY['WiFi', 'Projector', 'Sound System', 'AC', 'Cafeteria Nearby'], 'available', 4.9);
