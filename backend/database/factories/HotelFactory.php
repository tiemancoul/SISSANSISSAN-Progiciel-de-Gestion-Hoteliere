<?php

namespace Database\Factories;

use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<\App\Models\Hotel>
 */
class HotelFactory extends Factory
{
    public function definition(): array
    {
        $name = fake()->unique()->company();

        return ['name' => $name, 'slug' => Str::slug($name), 'is_active' => true];
    }
}
