<?php

namespace App\Enums;

enum Role: string
{
    case SuperAdmin = 'super_admin';
    case HotelAdmin = 'hotel_admin';
    case Receptionist = 'receptionist';
}
